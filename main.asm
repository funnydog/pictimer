        include "config.inc"
        include "delay.inc"
        include "i2c.inc"
        include "macro.inc"

        ;; fuses configuration
        config  FOSC = INTOSCIO, CFGPLLEN = OFF, CPUDIV = NOCLKDIV
        config  PWRTEN = ON, BOREN = NOSLP, BORV = 285, LPBOR = OFF
        config  WDTEN = OFF
        config  MCLRE = ON, PBADEN = OFF
        config  DEBUG = OFF, XINST = OFF, LVP = OFF, STVREN = OFF
        config  CP0 = OFF, CP1 = OFF, CP2 = OFF, CP3 = OFF, CPB = OFF, CPD = OFF
        config  WRT0 = OFF, WRT1 = OFF, WRT2 = OFF, WRT3 = OFF, WRTB = OFF, WRTD = OFF
        config  EBTR0 = OFF, EBTR1 = OFF, EBTR2 = OFF, EBTR3 = OFF, EBTRB = OFF

        ;; entry code section
.reset  code    0x0000
        bra     start

.isr    code    0x0008
        bra     isr

.data   udata

timeout res     2               ; timeout in seconds
bstate  res     10              ; 10 debounces
button  res     2               ; button status [0 = current, 1 = old]
dbuf    res     9               ; display buffer
tmp     res     2               ; temporary value
flags   res     1               ; signaling flags
bindex  res     1               ; current index
tsec    res     1               ; counter of tick seconds

.edata  code    0xF00000

saved   de      LOW(65), HIGH(65) ; saved timeout data

B       equ     BANKED

        ;; flags
LIGHTON equ     0               ; light on
LGHTOFF equ     1               ; light off
REFRESH equ     2               ; the display needs refresh
LEADING equ     3               ; don't print the leading zero

        ;; buttons
BSTART  equ     0               ; start
BPLUS   equ     1               ; increase timeout
BMINUS  equ     2               ; decrease timeout

        ;; main code
.main  code
isr:
        ;; debug AID
        btg     LATB, 3, A

        ;; handler for the CCP1IF interrupt
        btfss   PIR1, CCP1IF, A
        bra     isr0_end
        bcf     PIR1, CCP1IF, A

        ;; save the current state of the buttons
        movlb   0x0
        lfsr    FSR2, bstate
        movf    bindex, W, B
        addwf   FSR2L, F, A
        btfsc   STATUS, C, A
        incf    FSR2H, F, A
        movf    PORTA, W, A
        andlw   0x3F
        movwf   INDF2, A

        ;; compute the new button index
        incf    bindex, F, B
        movlw   -10
        addwf   bindex, W, B
        btfsc   STATUS, C, A
        clrf    bindex, B

        ;; do not count seconds if not needed
        btfss   flags, LIGHTON, B
        bra     isr0_end

        ;; check if timeout is zero
        movf    timeout+0, W, B
        iorwf   timeout+1, W, B
        bnz     isr0_l0

        ;; timeout is zero
        bcf     LATB, 2, A
        bcf     flags, LIGHTON, B
        bsf     flags, LGHTOFF, B
        bra     isr0_end

        ;; timeout is not zero
isr0_l0:
        ;; handle the seconds
        decfsz  tsec, F, B
        bra     isr0_end
        movlw   250
        movwf   tsec, B

        ;; decrease the timeout
        bsf     flags, REFRESH, B
        movlw   0
        decf    timeout+0, F, B
        subwfb  timeout+1, F, B

isr0_end:
isr_end:
        retfie  FAST

        ;; main code
start:
        ;; initialize the ports as digital outputs with value 0
        movlb   0xF             ; select the bank 0xF
        clrf    ANSELA, B       ; ANSEL A/B/C are not in ACCESS BANK
        clrf    ANSELB, B
        clrf    ANSELC, B
        clrf    LATA, B         ; clear the PORTA latches
        movlw   0x3F
        movwf   TRISA, B        ; set RA0..RA5 as inputs
        clrf    LATB, B         ; clear the PORTB latches
        clrf    TRISB, B        ; set RB0..RB7 as outputs
        clrf    LATC, B         ; clear the PORTC latches
        clrf    TRISC, B        ; set RC0..RC7 as outputs

        ;; speed up the internal clock to 16MHz
        bsf     OSCCON, IRCF2, B ; increase the freq to 16MHz
        delaycy 65536            ; a small delay for things to settle
        movlb   0x0              ; select the bank 0

        ;; initialize timeout
        call    read_timeout

        ;; initialize bstate
        lfsr    FSR0, bstate
        movlw   10
main_l0:
        clrf    POSTINC0, A
        addlw   -1
        bnz     main_l0

        ;; initialize dbuf
        call    seg_clear

        ;; acs variables
        clrf    flags, B
        clrf    bindex, B
        movlw   250
        movwf   tsec, B

        ;; initialize the periodicc TMR1
        ;; period = 16000 * 0.25 nsec = 4msec
        clrf    T1CON, A        ; no prescaler
        clrf    TMR1H, A
        clrf    TMR1L, A
        movlw   0x0B            ; configure CCP for special event
        movwf   CCP1CON, A
        bcf     CCPTMRS, C1TSEL ; configure CCP for TMR1
        movlw   HIGH(16000-1)
        movwf   CCPR1H, A
        movlw   LOW(16000-1)
        movwf   CCPR1L, A       ; set a period of 16000 * 0.25 nsec

        ;; enable the interrupts
        bcf     PIR1, CCP1IF, A
        bsf     PIE1, CCP1IE, A
        bsf     INTCON, GIE, A
        bsf     INTCON, PEIE, A

        ;; enable TMR1
        bsf     T1CON, TMR1ON, A

        ;; initialize I2C support
        call    i2c_init
        call    seg_init

        ;; write some numbers
        bcf     flags, LIGHTON, B
        bsf     flags, REFRESH, B

main_l1:
        ;; check if the light has been turned off
        ;; and reset the timeout value
        btfss   flags, LGHTOFF, B
        bra     main_l2
        bcf     flags, LGHTOFF, B
        call    read_timeout
        bsf     flags, REFRESH, B

main_l2:
        ;; check if we need to refresh the display
        ;; with the new values
        btfss   flags, REFRESH, B
        bra     main_l3

        ;; 16bit to BCD conversion
        call    b16_d5

        ;; convert the buffer to a proper
        ;; matrix representation taking into account
        ;; leading zeros
        bsf     flags, LEADING, B
        movf    dbuf+0, W, B    ; most significant digit
        call    get_digit
        movwf   dbuf+0, B

        movf    dbuf+2, W, B
        call    get_digit
        movwf   dbuf+2, B

        movf    dbuf+6, W, B
        call    get_digit
        movwf   dbuf+6, B

        bcf     flags, LEADING, B
        movf    dbuf+8, W, B    ; least significant digit
        call    get_digit
        movwf   dbuf+8, B

        call    seg_send_buf
        bcf     flags, REFRESH, B

        ;; switches
main_l3:
        ;; if LIGHTON do not read the user input
        btfsc   flags, LIGHTON, B
        bra     main_l1

        ;; read the buttons, save the old read
        movf    button+0, W, B
        movwf   button+1, B
        call    get_switches

        ;; check the button START
        btfss   button+0, BSTART, B
        bra     main_l4

        ;; check if timeout is zero
        movf    timeout+0, W, B
        iorwf   timeout+1, W, B
        bz      main_l4

        ;; set the start flags
        call    update_timeout
        bsf     LATB, 2, A
        movlw   1
        movwf   tsec, B
        movlw   1<<LIGHTON | 1<<REFRESH
        iorwf   flags, B

main_l4:
        ;; check the button PLUS
        btfss   button+0, BPLUS, B
        bra     main_l5
        btfsc   button+1, BPLUS, B
        bra     main_l5

        ;; increase the seconds
        incf    timeout+0, F, B
        btfsc   STATUS, C, A
        incf    timeout+1, F, B
        bsf     flags, REFRESH, B

main_l5:
        ;; check the button MINUS
        btfss   button+0, BMINUS, B
        bra     main_l1
        btfsc   button+1, BMINUS, B
        bra     main_l1

        ;; decrease the seconds
        movlw   0
        decf    timeout+0, F, B
        btfss   STATUS, C, A
        decf    timeout+1, F, B
        bc      main_l6

        ;; but not below 0
        clrf    timeout+0, B
        clrf    timeout+1, B
main_l6:
        bsf     flags, REFRESH, B
        bra     main_l1

        ;; initialize the display
        ;; duty cycle = 1/16
        ;; blink = off
seg_init:
        ltab    seg_init_cmd
        movlw   2
        call    i2c_send_tbl
        call    i2c_send_tbl
        call    i2c_send_tbl
        bra     i2c_send_tbl
seg_init_cmd    db      0xE0,0x21,0xE0,0xA3,0xE0,0xE1,0xE0,0x81

        ;; send the contents of dbuf
        ;; to the controller of the display
        ;; Positions of the digits
        ;;
        ;; 0123456789
        ;; d.d.:.d.d.
        ;;
seg_send_buf:
        call    i2c_start
        movlw   0xE0
        call    i2c_write
        movlw   0
        call    i2c_write
        movlw   9
        movwf   tmp, B
        lfsr    FSR0, dbuf
seg_send_l0:
        movf    POSTINC0, W, A
        call    i2c_write
        decf    tmp, F, B
        bnz     seg_send_l0
        bra     i2c_stop

        ;; clear the contents of dbuf
seg_clear:
        movlw   9
        lfsr    FSR0, dbuf
seg_clear_l0:
        clrf    POSTINC0, A
        addlw   -1
        bnz     seg_clear_l0
        return

        ;; get the digit led mask for a given digit
        ;; taking into account the LEADING zero
get_digit:
        andlw   0x0F
        bnz     get_digit_l0
        btfsc   flags, LEADING, B
        retlw   0
get_digit_l0:
        ltabw   get_digit_l1
        tblrd   *
        movf    TABLAT, W, A
        bcf     flags, LEADING, B
        return
get_digit_l1:
        db      0x3F,0x06,0x5B,0x4F
        db      0x66,0x6D,0x7D,0x07
        db      0x7F,0x6F,0x77,0x7C
        db      0x39,0x5E,0x79,0x71

        ;; get the debounced status of the switches
        ;; the status is debounced in the timer ISR
get_switches:
        movlw   10
        movwf   tmp, B
        lfsr    FSR0, bstate
        movlw   0xff
get_switches_l0:
        andwf   POSTINC0, W, A
        decfsz  tmp, F, B
        bra     get_switches_l0
        movwf   button, B
        return

        ;; read the timeout in EEPROM
read_timeout:
        lfsr    FSR0, timeout
        movlw   saved+0
        movwf   EEADR, A
        bcf     EECON1, EEPGD, A
        bcf     EECON1, CFGS, A
        movlw   2
        movwf   tmp, B
read_timeout_l0:
        bsf     EECON1, RD, A
        movf    EEDATA, W, A
        movwf   POSTINC0, A
        incf    EEADR, F, A
        decfsz  tmp, F, B
        bra     read_timeout_l0
        return

        ;; update the timeout in EEPROM
        ;; when different from timeout in memory
update_timeout:
        movlw   2
        movwf   tmp, B
        lfsr    FSR0, timeout
        movlw   saved+0
        movwf   EEADR, A
        bcf     EECON1, CFGS, A
        bcf     EECON1, EEPGD, A
        bsf     EECON1, WREN, A
        bcf     INTCON, GIE, A
update_timeout_l1:
        bsf     EECON1, RD, A
        movf    EEDATA, W, A
        subwf   INDF0, W, A
        bz      update_timeout_l2
        movf    INDF0, W, A
        movwf   EEDATA, A
        movlw   0x55
        movwf   EECON2, A
        movlw   0xAA
        movwf   EECON2, A
        bsf     EECON1, WR, A
        btfsc   EECON1, WR, A   ; wait for write to complete
        bra     $-2
update_timeout_l2:
        movf    POSTINC0, W, A
        incf    EEADR, F, A
        decfsz  tmp, F, B
        bra     update_timeout_l1

        bcf     EECON1, WREN, A
        bsf     INTCON, GIE, A
        return

        ;; convert the 16bit timeout value to BCD
        ;; saving the digits in dbuf[0,2,6,8]
b16_d5
        swapf   timeout+0, W, B ; partial ones sum in low byte
        addwf   timeout+0, W, B
        andlw   0x0f
        skpndc
        addlw   0x16
        skpndc
        addlw   0x06
        addlw   0x06
        skpdc
        addlw   -0x06           ; wmax=3:0

        btfsc   timeout+0, 4, B ; complete ones sum in low byte
        addlw   0x15+0x06
        skpdc
        addlw   -0x06           ; wmax=4:5
        movwf   dbuf+8, B       ; save sum in dbuf+8
;
;     8+      4+     2+     1+     8+     4+    2+    1+
;    20
;   100      60     30     15+
;   ----------------------------------------------------
;   128      64     32     16      8      4     2     1
;
        swapf   timeout+1, W, B ; partial ones sum in high byte
        addwf   timeout+1, W, B
        andlw   0x0f
        skpndc
        addlw   0x16
        skpndc
        addlw   0x06
        addlw   0x06
        skpdc
        addlw   -0x06           ; wmax=3:0

        btfsc   timeout+1, 0, B ; complete ones sum in high byte
        addlw   0x05+0x06
        skpdc
        addlw   -0x06           ; wmax=3:5

        btfsc   timeout+1, 4, B
        addlw   0x15+0x06
        skpdc
        addlw   -0x06           ; wmax=5:0

        addlw   0x06            ; include previous sum
        addwf   dbuf+8,w
        skpdc
        addlw   -0x06           ; wmax=9:5, ones sum ended

        movwf   dbuf+8, B
        movwf   dbuf+6, B
        swapf   dbuf+6, F, B
        movlw   0x0f
        andwf   dbuf+8, F, B    ; save total ones sum in dbuf+8
        andwf   dbuf+6, F, B    ; save partial tens sum in dbuf+6
;
;     8+      4+     2+     1+     8+     4+    2+    1+
;                           5+
;    60      80     90     10+                        5+
;   700     300    100     80     40     20    10    50
; 32000   16000   8000   4000   2000   1000   500   200
; ------------------------------------------------------
; 32768   16384   8192   4096   2048   1024   512   256
;
                                ; complete tens sum in low and high byte
        rrcf    timeout+1, W, B ; rotate right high byte once
        andlw   0x0f            ; clear high nibble
        addlw   0x06            ; adjust bcd
        skpdc
        addlw   -0x06           ; wmax=1:5

        addlw   0x06            ; include previous sum
        addwf   dbuf+6, W, B
        skpdc
        addlw   -0x06           ; wmax=2:4

        btfsc   timeout+0, 5, B
        addlw   0x03+0x06
        skpdc
        addlw   -0x06           ; wmax=2:7

        btfsc   timeout+0, 6, B
        addlw   0x06+0x06
        skpdc
        addlw   -0x06           ; wmax=3:3

        btfsc   timeout+0, 7, B
        addlw   0x12+0x06
        skpdc
        addlw   -0x06           ; wmax=4:5

        btfsc   timeout+1, 0, B
        addlw   0x25+0x06
        skpdc
        addlw   -0x06           ; wmax=7:0

        btfsc   timeout+1, 5, B
        addlw   0x09+0x06
        skpdc
        addlw   -0x06           ; wmax=7:9

        btfsc   timeout+1, 6, B
        addlw   0x08+0x06
        skpdc
        addlw   -0x06           ; wmax=8:7

        btfsc   timeout+1, 7, B
        addlw   0x06+0x06
        skpdc
        addlw   -0x06           ; wmax=9:3, tens sum ended

        movwf   dbuf+6          ; save total tens sum in dbuf+6
        swapf   dbuf+6, W, B
        andlw   0x0f            ; load partial hundreds sum in w
;
;     8+      4+     2+     1+     8+     4+    2+    1+
;    20+                    5+
;   100+     60+    30+    10+
;   ----------------------------------------------------
;   128      64     32     16      8      4     2     1
;
;     8+      4+     2+     1+     8+     4+    2+    1+
;                           5+
;    60+     80+    90+    10+                        5+
;   700     300    100     80+    40+    20+   10+   50+
; 32000   16000   8000   4000   2000   1000   500   200+
; ------------------------------------------------------
; 32768   16384   8192   4096   2048   1024   512   256
;
                                ; complete hundreds sum in high byte
        btfsc   timeout+1, 1, B
        addlw   0x05+0x06
        skpdc
        addlw   -0x06           ; wmax=1:4

        btfsc   timeout+1, 5, B
        addlw   0x01+0x06
        skpdc
        addlw   -0x06           ; wmax=1:5

        btfsc   timeout+1, 6, B
        addlw   0x03+0x06
        skpdc
        addlw   -0x06           ; wmax=1:8

        btfsc   timeout+1, 7, B
        addlw   0x07+0x06
        skpdc
        addlw   -0x06           ; wmax=2:5, hundreds sum ended

        movwf   dbuf+2, B       ; save total hundreds sum in dbuf+2
        swapf   dbuf+2, W, B
        movwf   dbuf+0, B       ; save partial thousands sum in dbuf+0
        movlw   0x0f            ; clear high nibble
        andwf   dbuf+6, F, B
        andwf   dbuf+2, F, B
        movlw   0x0f
        andwf   dbuf+0, F, B
;
;     8+      4+     2+     1+     8+     4+    2+    1+
;                           5+
;    60+     80+    90+    10+                        5+
;   700+    300+   100+    80+    40+    20+   10+   50+
; 32000   16000   8000   4000   2000   1000   500+  200+
; ------------------------------------------------------
; 32768   16384   8192   4096   2048   1024   512   256
;
                                ; complete thousands sum in low and high byte
        rrcf    timeout+1, W, B ; rotate right high byte twice
        movwf   tmp, B
        rrcf    tmp, W, B
        andlw   0x0f            ; clear high nibble
        addlw   0x06            ; adjust bcd
        skpdc
        addlw   -0x06           ; wmax=1:5

        addlw   0x06            ; include previous sum
        addwf   dbuf+0, W, B
        skpdc
        addlw   -0x06           ; wmax=1:7

        btfsc   timeout+1, 6, B
        addlw   0x16+0x06
        skpdc
        addlw   -0x06           ; wmax=3:3

        btfsc   timeout+1, 7, B
        addlw   0x32+0x06
        skpdc
        addlw   -0x06           ; wmax=6:5, thousands sum ended

        movwf   dbuf+0, B       ; save total thousands sum in dbuf+0
        movwf   tmp, B
        swapf   tmp, F, B       ; save ten-thousands sum in tmp
        movlw   0x0f            ; clear high nibble
        andwf   dbuf+0, F, B
        andwf   tmp, F, B
        return

        end
