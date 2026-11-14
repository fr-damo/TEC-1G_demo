;=====================================================================
;  TMS9918 "TEC-1G" demo  + "Music Banger" soundtrack  -  Z80
;  VDP data port = $BE, control port = $BF.  Speaker = bit 7 of port $01.
;  Load & run at $8000.
;
;  Visuals: dithered plasma, TEC-1G* sprite chain, orbiting stars,
;           rainbow copper bars, giant wavy LED "TEC-1G" scroller.
;  Audio:   the "Music Banger" bytebeat (by Anonymous), re-expressed
;           so it runs interleaved with the graphics:
;              out = ((rlc(D,C) | E) * 10) & $80   every sample
;              DE = sample counter, C = section 1..5
;           This is bit-for-bit the same sequence as the original
;           (H after LD H,D / LD L,D / C x ADD HL,HL is D rotated
;           left C times).  State lives in the alternate registers
;           (BC' DE' HL', AF' used as a save slot), and an SMP macro
;           is placed through every loop so a sample is output about
;           every 240 T-states, the same rate as the original loop.
;  No interrupts used (VDP status polled), runs with DI.
;  All VRAM writes are spaced >= 29 T-states (safe at 3.58 MHz).
;=====================================================================
        DEVICE NOSLOT64K
VDAT    EQU $BE
VCTL    EQU $BF
SPK     EQU $01             ; DSCAN latch, bit 7 = speaker

PAT0    EQU $0000
PAT2    EQU $1000
SPRPAT  EQU $1800
COL0    EQU $2000
COL2    EQU $3000
NAMES   EQU $3800
SAT     EQU $3B00

BARCH1  EQU 192
BARCH2  EQU 193
BIGROW  EQU 17

;--- one audio sample: 60 T-states, preserves all main registers ---
        MACRO SMP
        ex af,af'
        exx
        inc e
        call z,snext
        ld a,e
        or b
        ld l,a
        ld a,(hl)
        out (SPK),a
        exx
        ex af,af'
        ENDM

        MACRO PAD n
        DUP (n)/4
        nop
        EDUP
        ENDM

        ORG $8000
start:
        di
        ld sp,$C000
        xor a
        out (SPK),a
        ld hl,vdpregs
        ld b,0
.rg:    ld a,(hl)
        out (VCTL),a
        ld a,b
        or $80
        out (VCTL),a
        inc hl
        inc b
        ld a,b
        cp 8
        jr nz,.rg

        ld hl,0
        call vaddr
        ld bc,$4000
        xor a
        call vfill

        ld hl,PAT0
        call vaddr
        ld e,64
.dp:    ld hl,dither
        ld bc,64
        call vwrite
        dec e
        jr nz,.dp

        ld hl,PAT2
        call vaddr
        ld e,6
.bk:    ld hl,blocks
        ld bc,128
        call vwrite
        dec e
        jr nz,.bk
        ld hl,PAT2+BARCH1*8
        call vaddr
        ld a,$FF
        ld bc,16
        call vfill

        ld hl,SPRPAT
        call vaddr
        ld hl,sprpat
        ld bc,224
        call vwrite

        ld hl,NAMES+16*32
        call vaddr
        ld a,BARCH1
        ld bc,32
        call vfill
        ld hl,NAMES+23*32
        call vaddr
        ld a,BARCH2
        ld bc,32
        call vfill

        ld hl,vars
        ld bc,varsend-vars
.cv:    ld (hl),0
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.cv
        ld hl,colbuf
        ld b,64+8
.cc:    ld (hl),0
        inc hl
        djnz .cc
        ld hl,ellietext
        ld (txtptr),hl

        ; music state (alternate set): DE=counter, C=section, B=rlc(D,C)
        exx
        ld de,0
        ld bc,$0001
        ld h,high stbl
        exx

        xor a
        call setscene

        ld a,$C2
        out (VCTL),a
        ld a,$81
        out (VCTL),a

;=====================================================================
mainloop:
        call waitvb
        call putsprites
        call bars
        call plasma
        call bigscroll
        call calcsprites
        SMP
        ld hl,(frame)
        inc hl
        ld (frame),hl
        ld a,l
        or a
        jr nz,mainloop
        ld a,h
        and 1
        jr nz,mainloop
        ld a,(scene)
        inc a
        cp NSCENES
        jr c,.ok
        xor a
.ok:    call setscene
        jr mainloop

; wait for vblank, keep the music going at 240 T per poll
waitvb: in a,(VCTL)
.w:     SMP
        in a,(VCTL)
        rla
        ret c
        PAD 132
        jr .w

; advance music every 256 samples (counter high byte / section)
snext:  inc d
        jr nz,.rot
        inc c
        ld a,c
        cp 6
        jr c,.rot
        ld c,1
.rot:   ld a,d
        ld b,c
.r:     rlca
        djnz .r
        ld b,a
        ret

;---------------------------------------------------------------------
setscene:
        ld (scene),a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,scn2
        add hl,de
        ld de,wf
        ld bc,4
        ldir
        SMP
        ld a,(scene)
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,scenes
        add hl,de
        ld de,xm
        ld bc,8
        ldir
        ld a,(rampno)
        add a,a
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,ramp0
        add hl,de
        ld (rampp),hl
        SMP
        ld hl,COL0
        call vaddr
        call rampbank
rampbank:
        ld c,0
.g:     SMP
        ld hl,(rampp)
        ld a,c
        inc a
        and 31
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        add a,a
        add a,a
        add a,a
        add a,a
        ld b,a
        ld hl,(rampp)
        ld e,c
        add hl,de
        ld a,(hl)
        or b
        ld b,16                     ; 16 x 4 = 64 bytes
.o:     SMP
        out (VDAT),a
        PAD 40
        out (VDAT),a
        PAD 40
        out (VDAT),a
        PAD 40
        out (VDAT),a
        djnz .o
        inc c
        ld a,c
        cp 32
        jp nz,.g
        ret

;---------------------------------------------------------------------
plasma:
        ld hl,t1
        ld a,(s1)
        add a,(hl)
        ld (hl),a
        inc hl
        ld a,(s2)
        add a,(hl)
        ld (hl),a
        inc hl
        ld a,(s3)
        add a,(hl)
        ld (hl),a
        inc hl
        ld a,(s4)
        add a,(hl)
        ld (hl),a
        ld hl,palofs
        inc (hl)
        inc (hl)
        SMP

        ld a,(xm)
        ld c,a
        ld a,(t1)
        ld d,high sin128
        ld hl,colA
        ld b,16
.ca:    SMP
        DUP 4
        ld e,a
        ld a,(de)
        ld (hl),a
        inc l
        ld a,e
        add a,c
        EDUP
        PAD 48
        djnz .ca

        ld a,(dm)
        ld c,a
        ld a,(t3)
        ld hl,diag
        ld b,12
.dg:    SMP
        DUP 4
        ld e,a
        ld a,(de)
        ld (hl),a
        inc l
        ld a,e
        add a,c
        EDUP
        PAD 48
        djnz .dg

        ld a,(ym)
        ld c,a
        ld a,(t2)
        ld hl,rowB
        ld b,8
.rb:    SMP
        DUP 2
        ld e,a
        ld a,(de)
        push hl
        ld hl,palofs
        add a,(hl)
        pop hl
        ld (hl),a
        inc l
        ld a,e
        add a,c
        EDUP
        PAD 32
        djnz .rb
        ld a,(t4)
        ld hl,warp
        ld b,4
.wp:    SMP
        DUP 4
        ld e,a
        ld a,(de)
        rrca
        rrca
        and 31
        ld (hl),a
        inc l
        ld a,e
        add a,12
        EDUP
        djnz .wp

        ld hl,NAMES
        call vaddr
        SMP
        ld de,diag
        ld ix,rowB
.row:   ld c,(ix+0)
        ld a,(ix+16)
        ld l,a
        ld h,high colA
        push de
.k = 0
        DUP 32                      ; 32 cells, a sample every 5 cells
        IF .k % 5 == 0
        SMP
        ENDIF
        ld a,(de)                   ;  7
        inc e                       ;  4
        add a,(hl)                  ;  7
        inc l                       ;  4
        add a,c                     ;  4
        out (VDAT),a                ; 11
.k = .k + 1
        EDUP
        pop de
        inc e
        inc ix
        ld a,e
        cp 16
        jp nz,.row
        ret

;---------------------------------------------------------------------
        MACRO BARBYTE
        ld a,c
        and 15
        ld e,a
        ld d,0
        ld hl,rainbow
        add hl,de
        ld a,(hl)
        out (VDAT),a
        inc c
        ENDM

bars:
        ld hl,COL2+BARCH1*8
        call vaddr
        SMP
        ld a,(frame)
        ld c,a
        ld b,4
.b1:    SMP
        BARBYTE
        BARBYTE
        PAD 36
        djnz .b1
        ld a,(frame)
        neg
        ld c,a
        ld b,4
.b2:    SMP
        BARBYTE
        BARBYTE
        PAD 36
        djnz .b2
        ret

;---------------------------------------------------------------------
; Giant TEC-1G LED-dot scroller.  Column shifting is done
; with lookup tables so every column costs the same time.
        MACRO CELL dd,base
        ld a,e
        and 3
        add a,a
        add a,a
        ld b,a
        ld a,l
        and 3
        or b
        or base
        ld (iy+dd),a
        srl h
        rr l
        srl h
        rr l
        srl d
        rr e
        srl d
        rr e
        ENDM

        MACRO VBYTE                 ; 30 T, wraps within an 8-byte block
        ld a,(hl)
        out (VDAT),a
        inc l
        res 3,l
        ENDM

bigscroll:
        SMP
        ld hl,colbuf+1              ; scroll one dot column (66 x ldi)
        ld de,colbuf
        ld bc,66
.sl:    SMP
        DUP 11
        ldi
        EDUP
        jp pe,.sl

        ld hl,(txtptr)
        ld a,(hl)
        or a
        jr nz,.c
        ld hl,ellietext
        ld (txtptr),hl
        ld a,(hl)
.c:     sub 32
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        add hl,hl
        SMP
        ld de,colfont
        add hl,de
        ld a,(gcol)
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        ld (colbuf+63),a
        SMP
        ld a,(gcol)
        inc a
        cp 6
        jr c,.s
        ld hl,(txtptr)
        inc hl
        ld (txtptr),hl
        xor a
.s:     ld (gcol),a

        ld a,(ws)
        ld hl,wph
        add a,(hl)
        ld (hl),a
        ld c,a

        ld ix,colbuf
        ld iy,namebuf+64
        ld a,32
        ld (xcnt),a
.col:   SMP
        ld l,c
        ld h,high wav
        ld a,(hl)                   ; vertical offset 0..5
        add a,high shl0
        ld h,a
        ld a,(wf)
        add a,c
        ld c,a
        ld l,(ix+1)                 ; DE = right column << o
        ld e,(hl)
        set 7,l
        ld d,(hl)
        ld l,(ix+0)                 ; HL = left column << o
        ld a,(hl)
        set 7,l
        ld h,(hl)
        ld l,a
        PAD 44
        SMP
        CELL -64,$00
        PAD 52
        SMP
        CELL -32,$10
        PAD 52
        SMP
        CELL 0,$20
        PAD 52
        SMP
        CELL 32,$30
        PAD 52
        SMP
        CELL 64,$40
        PAD 52
        SMP
        CELL 96,$50
        inc ix
        inc ix
        inc iy
        ld a,(xcnt)
        dec a
        ld (xcnt),a
        jp nz,.col

        ld hl,NAMES+BIGROW*32       ; upload 6 rows of names
        call vaddr
        ld hl,namebuf
        ld b,16
.nu:    DUP 2
        SMP
        DUP 6
        ld a,(hl)
        out (VDAT),a
        inc l
        nop
        nop
        EDUP
        EDUP
        djnz .nu

        ; copper: lc[R*16+line] = cop[R*8+line+copofs]
        ld hl,copofs
        inc (hl)
        ld c,(hl)
        ld de,lc
        ld h,high cop
.n = 0
        DUP 48
        IF .n % 7 == 0
        SMP
        ENDIF
        ld l,c
        ld a,(hl)
        ld (de),a
        inc e
        inc c
        IF .n % 8 == 7
        ld a,e
        add a,8
        ld e,a
        ENDIF
.n = .n + 1
        EDUP

        ld hl,COL2                  ; 6 rows x 16 chars x 8 lines
        call vaddr
        ld hl,lc
        ld c,6
.cr:    DUP 21                      ; one row = 128 bytes, unrolled
        SMP
        DUP 6
        VBYTE
        EDUP
        EDUP
        SMP
        VBYTE
        VBYTE
        PAD 88
        ld a,l
        add a,16
        ld l,a
        dec c
        jp nz,.cr
        ret

;---------------------------------------------------------------------
calcsprites:
        ld a,(frame)
        ld c,a
        ld ix,satbuf
        ld b,0
.sp:    SMP
        ld a,b
        add a,a
        ld e,a
        add a,a
        add a,a
        add a,e
        ld e,a
        ld a,c
        add a,a
        sub e
        ld d,a
        ld a,(m2)                   ; a = d * (1, 2 or 3)
        and d
        add a,d
        ld e,a
        ld a,(m3)
        and d
        add a,e
        ld l,a
        ld h,high sinx
        ld a,(hl)
        add a,8
        ld (ix+1),a
        ld a,d
        add a,a
        add a,64
        ld l,a
        ld h,high siny2
        ld a,(hl)
        ld (ix+0),a
        SMP
        ld e,b
        ld d,0
        ld hl,chain14
        add hl,de
        ld a,(hl)
        ld (ix+2),a
        cp 24
        jr nz,.let
        ld a,c                      ; star: twinkle yellow / white
        and 8
        ld a,11
        jr z,.sc
        ld a,15
        jr .sc
.let:   ld a,c
        rrca
        rrca
        rrca
        add a,b
        and 15
        ld e,a
        ld d,0
        ld hl,sprcol
        add hl,de
        ld a,(hl)
.sc:    ld (ix+3),a
        ld de,4
        add ix,de
        inc b
        ld a,b
        cp 14
        jp nz,.sp

.ht:    SMP
        ld a,b
        and 3
        rrca
        rrca
        ld e,a
        ld a,c
        add a,a
        add a,c
        add a,e
        ld l,a
        ld h,high sinx
        ld a,(hl)
        add a,8
        ld (ix+1),a
        ld a,l
        add a,64
        ld l,a
        ld h,high siny2
        ld a,(hl)
        ld (ix+0),a
        PAD 48
        SMP
        ld (ix+2),24
        ld a,c
        rrca
        rrca
        add a,b
        and 3
        ld e,a
        ld d,0
        ld hl,heartcol
        add hl,de
        ld a,(hl)
        ld (ix+3),a
        PAD 28
        ld de,4
        add ix,de
        inc b
        ld a,b
        cp 16
        jp nz,.ht
        ret

putsprites:
        ld hl,SAT
        call vaddr
        ld a,(frame)
        ld c,a
        add a,a
        add a,a
        add a,c
        and 15
        ld c,a
        ld b,16
.ps:    SMP
        ld a,c
        and 15
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,satbuf
        add hl,de
        ld a,(hl)
        out (VDAT),a
        inc hl
        ld a,(hl)
        nop
        out (VDAT),a
        inc hl
        ld a,(hl)
        nop
        out (VDAT),a
        inc hl
        ld a,(hl)
        nop
        out (VDAT),a
        PAD 8
        inc c
        djnz .ps
        ld a,$D0
        out (VDAT),a
        ret

;---------------------------------------------------------------------
vaddr:  ld a,l
        out (VCTL),a
        ld a,h
        or $40
        out (VCTL),a
        ret

vwrite: ld a,(hl)
        out (VDAT),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,vwrite
        ret

vfill:  ld d,a
.f:     ld a,d
        out (VDAT),a
        dec bc
        ld a,b
        or c
        jr nz,.f
        ret

;---------------------------------------------------------------------
vdpregs: db $02,$82,$0E,$FF,$03,$76,$03,$01

NSCENES EQU 4
scenes:
        db 4,6,3, 3,$FE,5, 2, 0
        db 8,3,6, $FD,4,2, 3, 1
        db 2,10,9, 5,2,$FD, 1, 2
        db 6,6,2, 2,3,4, 4, 0
; scroller wave freq, wave speed, sprite x-multiplier masks (x2, x3)
scn2:
        db 8,6,0,0                  ; gentle wave,   x*1
        db 20,10,$FF,0              ; tight ripple,  x*2
        db 0,9,$FF,$FF              ; bounce,        x*3
        db 4,$FB,$FF,0              ; reverse swell, x*2
chain14: db 0,4,8,12,16,20,24,0,4,8,12,16,20,24   ; T E C - 1 G star

ellietext: db "TEC-1G  <  ",0

        ALIGN 256
sin128:
    db $40,$41,$43,$44,$46,$47,$49,$4A,$4C,$4D,$4F,$50,$52,$53,$55,$56
    db $58,$59,$5B,$5C,$5D,$5F,$60,$61,$63,$64,$65,$67,$68,$69,$6A,$6B
    db $6C,$6D,$6F,$70,$71,$72,$73,$73,$74,$75,$76,$77,$78,$78,$79,$7A
    db $7A,$7B,$7B,$7C,$7C,$7D,$7D,$7D,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$7F
    db $7F,$7F,$7F,$7F,$7F,$7F,$7E,$7E,$7E,$7D,$7D,$7D,$7C,$7C,$7B,$7B
    db $7A,$7A,$79,$78,$78,$77,$76,$75,$74,$73,$73,$72,$71,$70,$6F,$6D
    db $6C,$6B,$6A,$69,$68,$67,$65,$64,$63,$61,$60,$5F,$5D,$5C,$5B,$59
    db $58,$56,$55,$53,$52,$50,$4F,$4D,$4C,$4A,$49,$47,$46,$44,$43,$41
    db $40,$3E,$3C,$3B,$39,$38,$36,$35,$33,$32,$30,$2F,$2D,$2C,$2A,$29
    db $27,$26,$24,$23,$22,$20,$1F,$1E,$1C,$1B,$1A,$18,$17,$16,$15,$14
    db $13,$12,$10,$0F,$0E,$0D,$0C,$0C,$0B,$0A,$09,$08,$07,$07,$06,$05
    db $05,$04,$04,$03,$03,$02,$02,$02,$01,$01,$01,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$01,$01,$01,$02,$02,$02,$03,$03,$04,$04
    db $05,$05,$06,$07,$07,$08,$09,$0A,$0B,$0C,$0C,$0D,$0E,$0F,$10,$12
    db $13,$14,$15,$16,$17,$18,$1A,$1B,$1C,$1E,$1F,$20,$22,$23,$24,$26
    db $27,$29,$2A,$2C,$2D,$2F,$30,$32,$33,$35,$36,$38,$39,$3B,$3C,$3E
sinx:
    db $70,$72,$75,$78,$7A,$7D,$80,$83,$85,$88,$8B,$8D,$90,$92,$95,$98
    db $9A,$9D,$9F,$A2,$A4,$A6,$A9,$AB,$AD,$B0,$B2,$B4,$B6,$B8,$BA,$BC
    db $BE,$C0,$C2,$C4,$C6,$C7,$C9,$CB,$CC,$CE,$CF,$D1,$D2,$D3,$D4,$D5
    db $D7,$D8,$D8,$D9,$DA,$DB,$DC,$DC,$DD,$DD,$DE,$DE,$DE,$DF,$DF,$DF
    db $DF,$DF,$DF,$DF,$DE,$DE,$DE,$DD,$DD,$DC,$DC,$DB,$DA,$D9,$D8,$D8
    db $D7,$D5,$D4,$D3,$D2,$D1,$CF,$CE,$CC,$CB,$C9,$C7,$C6,$C4,$C2,$C0
    db $BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AD,$AB,$A9,$A6,$A4,$A2,$9F,$9D
    db $9A,$98,$95,$92,$90,$8D,$8B,$88,$85,$83,$80,$7D,$7A,$78,$75,$72
    db $70,$6D,$6A,$67,$65,$62,$5F,$5C,$5A,$57,$54,$52,$4F,$4D,$4A,$47
    db $45,$42,$40,$3D,$3B,$39,$36,$34,$32,$2F,$2D,$2B,$29,$27,$25,$23
    db $21,$1F,$1D,$1B,$19,$18,$16,$14,$13,$11,$10,$0E,$0D,$0C,$0B,$0A
    db $08,$07,$07,$06,$05,$04,$03,$03,$02,$02,$01,$01,$01,$00,$00,$00
    db $00,$00,$00,$00,$01,$01,$01,$02,$02,$03,$03,$04,$05,$06,$07,$07
    db $08,$0A,$0B,$0C,$0D,$0E,$10,$11,$13,$14,$16,$18,$19,$1B,$1D,$1F
    db $21,$23,$25,$27,$29,$2B,$2D,$2F,$32,$34,$36,$39,$3B,$3D,$40,$42
    db $45,$47,$4A,$4D,$4F,$52,$54,$57,$5A,$5C,$5F,$62,$65,$67,$6A,$6D
siny2:
    db $38,$39,$3A,$3C,$3D,$3E,$40,$41,$42,$44,$45,$46,$48,$49,$4A,$4B
    db $4D,$4E,$4F,$50,$52,$53,$54,$55,$56,$57,$59,$5A,$5B,$5C,$5D,$5E
    db $5F,$60,$61,$62,$62,$63,$64,$65,$66,$66,$67,$68,$68,$69,$6A,$6A
    db $6B,$6B,$6C,$6C,$6D,$6D,$6D,$6E,$6E,$6E,$6E,$6F,$6F,$6F,$6F,$6F
    db $6F,$6F,$6F,$6F,$6F,$6F,$6E,$6E,$6E,$6E,$6D,$6D,$6D,$6C,$6C,$6B
    db $6B,$6A,$6A,$69,$68,$68,$67,$66,$66,$65,$64,$63,$62,$62,$61,$60
    db $5F,$5E,$5D,$5C,$5B,$5A,$59,$57,$56,$55,$54,$53,$52,$50,$4F,$4E
    db $4D,$4B,$4A,$49,$48,$46,$45,$44,$42,$41,$40,$3E,$3D,$3C,$3A,$39
    db $38,$36,$35,$33,$32,$31,$2F,$2E,$2D,$2B,$2A,$29,$27,$26,$25,$24
    db $22,$21,$20,$1F,$1D,$1C,$1B,$1A,$19,$18,$16,$15,$14,$13,$12,$11
    db $10,$0F,$0E,$0D,$0D,$0C,$0B,$0A,$09,$09,$08,$07,$07,$06,$05,$05
    db $04,$04,$03,$03,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$02,$02,$02,$03,$03,$04
    db $04,$05,$05,$06,$07,$07,$08,$09,$09,$0A,$0B,$0C,$0D,$0D,$0E,$0F
    db $10,$11,$12,$13,$14,$15,$16,$18,$19,$1A,$1B,$1C,$1D,$1F,$20,$21
    db $22,$24,$25,$26,$27,$29,$2A,$2B,$2D,$2E,$2F,$31,$32,$33,$35,$36
wav:
    db $02,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
    db $03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
    db $04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
    db $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
    db $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
    db $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04
    db $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
    db $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
    db $03,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
    db $02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
cop:
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
    db $61,$61,$81,$81,$91,$91,$B1,$B1,$A1,$A1,$31,$31,$21,$21,$C1,$C1
    db $71,$71,$51,$51,$41,$41,$D1,$D1,$E1,$E1,$F1,$F1,$B1,$B1,$91,$91
dither:
    db $00,$00,$00,$00,$00,$00,$00,$00,$88,$00,$22,$00,$88,$00,$22,$00
    db $AA,$00,$AA,$00,$AA,$00,$AA,$00,$AA,$44,$AA,$11,$AA,$44,$AA,$11
    db $AA,$55,$AA,$55,$AA,$55,$AA,$55,$EE,$55,$BB,$55,$EE,$55,$BB,$55
    db $FF,$55,$FF,$55,$FF,$55,$FF,$55,$FF,$DD,$FF,$77,$FF,$DD,$FF,$77
ramp0:
    db $01,$04,$04,$05,$05,$07,$07,$0F,$0F,$07,$07,$05,$05,$04,$04,$01
    db $01,$06,$06,$08,$08,$09,$09,$0B,$0B,$09,$09,$08,$08,$06,$06,$01
ramp1:
    db $01,$0C,$0C,$02,$02,$03,$03,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$06
    db $06,$0D,$0D,$05,$05,$07,$07,$0F,$0F,$0E,$0E,$05,$05,$04,$04,$01
ramp2:
    db $06,$08,$09,$0B,$0F,$0B,$09,$08,$06,$0D,$05,$07,$0F,$07,$05,$0D
    db $0C,$02,$03,$0B,$0F,$0A,$09,$06,$04,$05,$07,$0E,$0F,$0E,$05,$04
blocks:
    db $00,$00,$00,$00,$00,$00,$00,$00,$E0,$E0,$E0,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$E0,$E0,$E0,$00,$E0,$E0,$E0,$00,$E0,$E0,$E0,$00
    db $0E,$0E,$0E,$00,$00,$00,$00,$00,$EE,$EE,$EE,$00,$00,$00,$00,$00
    db $0E,$0E,$0E,$00,$E0,$E0,$E0,$00,$EE,$EE,$EE,$00,$E0,$E0,$E0,$00
    db $00,$00,$00,$00,$0E,$0E,$0E,$00,$E0,$E0,$E0,$00,$0E,$0E,$0E,$00
    db $00,$00,$00,$00,$EE,$EE,$EE,$00,$E0,$E0,$E0,$00,$EE,$EE,$EE,$00
    db $0E,$0E,$0E,$00,$0E,$0E,$0E,$00,$EE,$EE,$EE,$00,$0E,$0E,$0E,$00
    db $0E,$0E,$0E,$00,$EE,$EE,$EE,$00,$EE,$EE,$EE,$00,$EE,$EE,$EE,$00
colfont:
    db $00,$00,$00,$00,$00,$00,$00,$00,$5F,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$03,$00,$00,$00
    db $00,$1C,$22,$41,$00,$00,$00,$41,$22,$1C,$00,$00,$08,$2A,$1C,$2A
    db $08,$00,$08,$08,$3E,$08,$08,$00,$00,$00,$50,$30,$00,$00,$08,$08
    db $08,$08,$08,$00,$00,$60,$60,$00,$00,$00,$40,$30,$08,$06,$01,$00
    db $3E,$51,$49,$45,$3E,$00,$00,$42,$7F,$40,$00,$00,$62,$51,$49,$49
    db $46,$00,$21,$41,$45,$4B,$31,$00,$18,$14,$12,$7F,$10,$00,$27,$45
    db $45,$45,$39,$00,$3C,$4A,$49,$49,$30,$00,$01,$71,$09,$05,$03,$00
    db $36,$49,$49,$49,$36,$00,$06,$49,$49,$29,$1E,$00,$00,$36,$36,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$24,$1C,$0F,$1C,$24,$00,$14,$14
    db $14,$14,$14,$00,$00,$00,$00,$00,$00,$00,$02,$01,$51,$09,$06,$00
    db $00,$00,$00,$00,$00,$00,$7E,$09,$09,$09,$7E,$00,$7F,$49,$49,$49
    db $36,$00,$3E,$41,$41,$41,$22,$00,$7F,$41,$41,$22,$1C,$00,$7F,$49
    db $49,$49,$41,$00,$7F,$09,$09,$09,$01,$00,$3E,$41,$49,$49,$7A,$00
    db $7F,$08,$08,$08,$7F,$00,$00,$41,$7F,$41,$00,$00,$20,$40,$41,$3F
    db $01,$00,$7F,$08,$14,$22,$41,$00,$7F,$40,$40,$40,$40,$00,$7F,$02
    db $0C,$02,$7F,$00,$7F,$04,$08,$10,$7F,$00,$3E,$41,$41,$41,$3E,$00
    db $7F,$09,$09,$09,$06,$00,$3E,$41,$51,$21,$5E,$00,$7F,$09,$19,$29
    db $46,$00,$46,$49,$49,$49,$31,$00,$01,$01,$7F,$01,$01,$00,$3F,$40
    db $40,$40,$3F,$00,$1F,$20,$40,$20,$1F,$00,$3F,$40,$38,$40,$3F,$00
    db $63,$14,$08,$14,$63,$00,$03,$04,$78,$04,$03,$00,$61,$51,$49,$45
    db $43,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
rainbow:
    db $61,$81,$91,$A1,$B1,$31,$21,$C1,$71,$51,$41,$D1,$D1,$41,$51,$71
sprcol:
    db $09,$0B,$03,$07,$05,$0D,$0F,$0A,$09,$0B,$03,$07,$05,$0D,$0F,$0A
heartcol:
    db $0B,$0F,$0A,$0F
chainpat:
    db $00,$04,$04,$08,$00,$0C
sprpat:
    db $00,$1F,$1F,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
    db $00,$F8,$F8,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$00
    db $00,$1F,$1F,$18,$18,$18,$18,$1F,$1F,$18,$18,$18,$18,$1F,$1F,$00
    db $00,$F8,$F8,$00,$00,$00,$00,$E0,$E0,$00,$00,$00,$00,$F8,$F8,$00
    db $00,$07,$07,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$07,$07,$00
    db $00,$E0,$E0,$18,$18,$00,$00,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
    db $00,$00,$00,$00,$00,$00,$00,$1F,$1F,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$F8,$F8,$00,$00,$00,$00,$00,$00,$00
    db $00,$01,$01,$07,$07,$01,$01,$01,$01,$01,$01,$01,$01,$07,$07,$00
    db $00,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$E0,$E0,$00
    db $00,$07,$07,$18,$18,$18,$18,$19,$19,$18,$18,$18,$18,$07,$07,$00
    db $00,$E0,$E0,$18,$18,$00,$00,$F8,$F8,$18,$18,$18,$18,$F8,$F8,$00
    db $00,$01,$01,$01,$03,$63,$FF,$7F,$1F,$07,$07,$0F,$1E,$1C,$18,$00
    db $00,$80,$80,$80,$C0,$C6,$FF,$FE,$F8,$E0,$E0,$F0,$78,$38,$18,$00

        ALIGN 256
stbl:
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80
    db $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$80
    db $80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80
    db $80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80
    db $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$80
    db $80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80
    db $80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
shl0:
    db $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
    db $10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F
    db $20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F
    db $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F
    db $40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F
    db $50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F
    db $60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F
    db $70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
shl1:
    db $00,$02,$04,$06,$08,$0A,$0C,$0E,$10,$12,$14,$16,$18,$1A,$1C,$1E
    db $20,$22,$24,$26,$28,$2A,$2C,$2E,$30,$32,$34,$36,$38,$3A,$3C,$3E
    db $40,$42,$44,$46,$48,$4A,$4C,$4E,$50,$52,$54,$56,$58,$5A,$5C,$5E
    db $60,$62,$64,$66,$68,$6A,$6C,$6E,$70,$72,$74,$76,$78,$7A,$7C,$7E
    db $80,$82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E
    db $A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE
    db $C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE
    db $E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
shl2:
    db $00,$04,$08,$0C,$10,$14,$18,$1C,$20,$24,$28,$2C,$30,$34,$38,$3C
    db $40,$44,$48,$4C,$50,$54,$58,$5C,$60,$64,$68,$6C,$70,$74,$78,$7C
    db $80,$84,$88,$8C,$90,$94,$98,$9C,$A0,$A4,$A8,$AC,$B0,$B4,$B8,$BC
    db $C0,$C4,$C8,$CC,$D0,$D4,$D8,$DC,$E0,$E4,$E8,$EC,$F0,$F4,$F8,$FC
    db $00,$04,$08,$0C,$10,$14,$18,$1C,$20,$24,$28,$2C,$30,$34,$38,$3C
    db $40,$44,$48,$4C,$50,$54,$58,$5C,$60,$64,$68,$6C,$70,$74,$78,$7C
    db $80,$84,$88,$8C,$90,$94,$98,$9C,$A0,$A4,$A8,$AC,$B0,$B4,$B8,$BC
    db $C0,$C4,$C8,$CC,$D0,$D4,$D8,$DC,$E0,$E4,$E8,$EC,$F0,$F4,$F8,$FC
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
shl3:
    db $00,$08,$10,$18,$20,$28,$30,$38,$40,$48,$50,$58,$60,$68,$70,$78
    db $80,$88,$90,$98,$A0,$A8,$B0,$B8,$C0,$C8,$D0,$D8,$E0,$E8,$F0,$F8
    db $00,$08,$10,$18,$20,$28,$30,$38,$40,$48,$50,$58,$60,$68,$70,$78
    db $80,$88,$90,$98,$A0,$A8,$B0,$B8,$C0,$C8,$D0,$D8,$E0,$E8,$F0,$F8
    db $00,$08,$10,$18,$20,$28,$30,$38,$40,$48,$50,$58,$60,$68,$70,$78
    db $80,$88,$90,$98,$A0,$A8,$B0,$B8,$C0,$C8,$D0,$D8,$E0,$E8,$F0,$F8
    db $00,$08,$10,$18,$20,$28,$30,$38,$40,$48,$50,$58,$60,$68,$70,$78
    db $80,$88,$90,$98,$A0,$A8,$B0,$B8,$C0,$C8,$D0,$D8,$E0,$E8,$F0,$F8
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
    db $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
    db $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
    db $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
shl4:
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
    db $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
    db $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
    db $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
    db $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
    db $07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07
shl5:
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$20,$40,$60,$80,$A0,$C0,$E0,$00,$20,$40,$60,$80,$A0,$C0,$E0
    db $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01
    db $02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03,$03,$03
    db $04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05
    db $06,$06,$06,$06,$06,$06,$06,$06,$07,$07,$07,$07,$07,$07,$07,$07
    db $08,$08,$08,$08,$08,$08,$08,$08,$09,$09,$09,$09,$09,$09,$09,$09
    db $0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B
    db $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
    db $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F


codeend:
;---------------------------------------------------------------------
bss     EQU (codeend + 255) & $FF00
colA    EQU bss
diag    EQU bss+$100
rowB    EQU bss+$200
warp    EQU rowB+16
satbuf  EQU bss+$300
colbuf  EQU bss+$340            ; 64 (+ slack for 66-byte shift)
namebuf EQU bss+$400            ; 192, inside one page (inc l)
lc      EQU bss+$500            ; 6 blocks x 16 bytes (res 3,l wraps 8)
vars    EQU bss+$600
xm      EQU vars+0
ym      EQU vars+1
dm      EQU vars+2
s1      EQU vars+3
s2      EQU vars+4
s3      EQU vars+5
s4      EQU vars+6
rampno  EQU vars+7
t1      EQU vars+8
t2      EQU vars+9
t3      EQU vars+10
t4      EQU vars+11
palofs  EQU vars+12
frame   EQU vars+13
scene   EQU vars+15
rampp   EQU vars+16
wf      EQU vars+18
ws      EQU vars+19
m2      EQU vars+20
m3      EQU vars+21
wph     EQU vars+22
copofs  EQU vars+23
txtptr  EQU vars+24
gcol    EQU vars+26
xcnt    EQU vars+27
varsend EQU vars+28

        ASSERT bss+$700 < $BF00
        ASSERT codeend - start <= $4000
        SAVEBIN "tec1g.bin",start,codeend-start
