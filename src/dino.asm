org 0x7c00
use16

%define clock_ms 0x7e00 ; in RAM right after the boot sector
%define dino_y   0x7e04
%define dino_vel 0x7e06

%define bg_color 0x1e
%define fg_color 0x18

entry:
    ; set video mode 13h (https://ibm.retropc.se/video/bios_video_modes.html)
    xor ah, ah
    mov al, 13h
    int 10h
    ; set fs = VGA buffer
    mov ax, 0xa000
    mov fs, ax

    ; fill screen
    mov cx, 320 * 200
    xor di, di
    .iter:
        mov byte [fs:di], bg_color
        inc di
        loop .iter

    ; draw ground
    mov dl, fg_color
    mov si, ground_sprite
    xor bx, bx
    mov dh, 158
    mov cx, 20
    .ground:
        call draw_sprite
        add bx, 16
        loop .ground

    ; initialize vars
    ; mov dword [clock_ms], 0
    mov byte [dino_y], 136
    ; mov byte [dino_vel], 0

    ; set PIT channel 0 frequency (1kHz)
    mov ax, 1193182 / 1000
    out 0x40, al
    mov al, ah
    out 0x40, al
    ; set PIT channel 2 (PC speaker) frequency (250Hz)
    mov al, 0xb6
    out 0x43, al
    mov ax, 1193182 / 250
    out 0x42, al
    mov al, ah
    out 0x42, al
    ; set IRQ0 handler
    mov ax, cs
    mov word [0x0022], ax
    mov word [0x0020], irq0

infloop:
    jmp $

irq0:
    ; clear dino at old position
    mov si, dino_sprite
    mov dl, bg_color
    mov bx, 20
    mov dh, byte [dino_y]
    call draw_sprite

    ; shift cacti and ground to the left every 6ms
    mov cx, 6
    mov bx, .ground_cont
    call test_ms
    ; shift cacti (no wrap-around)
    mov cx, 33
    mov bx, 125
    xor dx, dx
    call shift_rect_left
    ; shift ground (wrap around)
    mov cx, 8
    mov bx, 158
    inc dx
    call shift_rect_left
    .ground_cont:

    ; draw new cacti every 750ms
    mov cx, 750
    mov bx, .cactus_cont
    call test_ms
    mov si, cactus_sprite
    mov dl, fg_color
    mov bx, 304
    mov dh, 146
    call draw_sprite
    .cactus_cont:

    ; update dino position and stop sound every 30ms
    mov cx, 30
    mov bx, .noupd
    call test_ms
    ; stop sound
    xor al, al
    out 0x61, al
    ; update pos
    mov al, byte [dino_vel]
    sub byte [dino_y], al
    cmp byte [dino_y], 136
    jae .nodown
    sub byte [dino_vel], 1
    jmp .noupd
    .nodown:
    mov byte [dino_y], 136
    .noupd:

    ; check keypress
    mov ah, 1
    int 16h
    jz .nostroke
    ; remove from buffer
    xor ah, ah
    int 16h
    ; check dino pos
    cmp byte [dino_y], 136
    jne .nostroke
    ; make our dino jump up and play a sound
    mov al, 3
    out 0x61, al
    mov byte [dino_vel], 7
    .nostroke:

    ; check collision
    mov bx, word [dino_y]
    mov ax, 320
    mul bx
    mov bx, ax
    mov dl, fg_color
    cmp byte [fs:bx+(13*320)+34], dl
    je infloop
    cmp byte [fs:bx+(15*320)+33], dl
    je infloop
    cmp byte [fs:bx+(18*320)+32], dl
    je infloop

    ; draw dino at new position
    mov si, dino_sprite
    mov bx, 20
    mov dh, byte [dino_y]
    call draw_sprite ; dl=fg_color

    ; advance clock
    inc dword [clock_ms]

    ; EOI
    mov al, 0x20
    out 0x20, al
    iret

;description:
; tests whether or not clock_ms % N == 0
;input:
; CX = N
; BX = address to jump to if the test failed
;      (if the test succeeded the subroutine returns)
test_ms:
    mov di, clock_ms
    mov ax, word [di]
    mov dx, word [di+2]
    div cx
    cmp dx, 0
    jne .fail
    ret
    .fail:
        add sp, 2 ; dummy pop of the return address
        jmp bx

;description:
; shifts a row of pixels to the left
;input:
; BX = Y position
; DX = whether or not to wrap around (0 = false, 1..255 = true)
shift_row_left:
    ; save regs
    push cx
    push dx
    ; calculate start of line
    mov ax, 320
    mul bx
    mov di, ax
    mov cx, 319
    ; do the thing
    .iter:
        mov al, byte [fs:di+1]
        mov byte [fs:di], al
        inc di
        loop .iter
    ; wrap around (restore DX prematurely to check if we need to)
    pop dx
    cmp dx, 0
    je .nowrap
    mov al, byte [fs:di-319]
    mov byte [fs:di], al
    .nowrap:
    ; restore regs
    pop cx
    ret

;description:
; shifts a rectangle starting at X=0 with a width of 320 to the left
;input:
; BX = Y position
; CX = height
; DX = whether or not to wrap around (0 = false, 1..255 = true)
shift_rect_left:
    .iter:
        call shift_row_left
        inc bx
        loop .iter
    ret

;description:
; draws a sprite
;input:
; DS:SI = sprite data
; BX = X coord
; DH = Y coord
; DL = foreground color
draw_sprite:
    ; save regs
    pusha
    ; calculate vmem offset
    mov ax, 160
    mul dh
    shl ax, 1
    mov di, ax
    add di, bx
    ; read height into cx
    mov dh, byte [si]
    movzx cx, dh
    and cx, 0x1f
    add cl, 2
    ; keep width in dh
    shr dh, 5
    inc si
.row:
    push dx
    .chunk:
        ; read chunk
        mov ah, byte [si]
        mov bp, 8
        .pixel:
            test ah, 0x80 ; test leftmost pixel
            jz .bg_pixel
            mov byte [fs:di], dl ; foreground pixel
            .bg_pixel:
            shl ah, 1
            inc di
            dec bp
            jnz .pixel
        inc si
        dec dh
        jnz .chunk
    ; go to second row
    pop dx
    add di, 320
    movzx ax, dh
    shl ax, 3
    sub di, ax
    loop .row
.return:
    ; restore regs
    popa
    ret

ground_sprite: ; 17 bytes
    db (2 << 5) | (6 << 0) ; 4 bytes (32px) wide, 6+2=8 bytes (8px) tall
    db 11111111b, 11111111b
    db 10000000b, 10000000b
    db 00001000b, 01000000b
    db 00000000b, 00000010b
    db 00100000b, 00010000b
    db 00000000b, 01000000b
    db 00000001b, 01000000b
    db 00000000b, 00000001b
cactus_sprite: ; 11 bytes
    db (1 << 5) | (10 << 0)
    db 00001000b
    db 00011010b
    db 10011011b
    db 11011011b
    db 11011011b
    db 11011011b
    db 11011111b
    db 11111110b
    db 01111000b
    db 00011000b
    db 00011000b
    db 00011000b
dino_sprite: ; 67 bytes! MUHHHHH BLOATT!!!!!
    db (3 << 5) | (20 << 0)
    db 00000000b, 00011111b, 11100000b
    db 00000000b, 00111111b, 11110000b
    db 00000000b, 00110111b, 11110000b
    db 00000000b, 00111111b, 11110000b
    db 00000000b, 00111111b, 11110000b
    db 00000000b, 00111111b, 11110000b
    db 00000000b, 00111110b, 00000000b
    db 00000000b, 00111111b, 11000000b
    db 10000000b, 01111100b, 00000000b
    db 10000001b, 11111100b, 00000000b
    db 11000011b, 11111111b, 00000000b
    db 11100111b, 11111101b, 00000000b
    db 11111111b, 11111100b, 00000000b
    db 11111111b, 11111100b, 00000000b
    db 01111111b, 11111000b, 00000000b
    db 00111111b, 11111000b, 00000000b
    db 00011111b, 11110000b, 00000000b
    db 00001111b, 11110000b, 00000000b
    db 00000111b, 00110000b, 00000000b
    db 00000110b, 00100000b, 00000000b
    db 00000100b, 00100000b, 00000000b
    db 00000110b, 00110000b, 00000000b

times 510 - ($-$$) db 0 ; zero padding
dw 0xAA55 ; boot sector signature