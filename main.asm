
        include "config.inc"
        include "delay.inc"
	include "i2c.inc"
        include "usart.inc"

        ;; fuses configuration
	config	FOSC = INTOSCIO, CFGPLLEN = OFF, CPUDIV = NOCLKDIV
	config	PWRTEN = ON, BOREN = NOSLP, BORV = 285, LPBOR = OFF
	config  WDTEN = OFF
	config	MCLRE = ON, PBADEN = OFF
	config	DEBUG = OFF, XINST = ON, LVP = OFF, STVREN = OFF
	config	CP0 = OFF, CP1 = OFF, CP2 = OFF, CP3 = OFF, CPB = OFF, CPD = OFF
	config  WRT0 = OFF, WRT1 = OFF, WRT2 = OFF, WRT3 = OFF, WRTB = OFF, WRTD = OFF
        config	EBTR0 = OFF, EBTR1 = OFF, EBTR2 = OFF, EBTR3 = OFF, EBTRB = OFF

        ;; entry code section
.reset	code    0x0000
        bra     start

.isr	code	0x0008
	bra	isr

.data   udata

setout	res	2		; preset timeout
timeout	res	2		; timeout in seconds
bstate  res	10		; 10 debounces
button	res	2		; button status
dbuf	res	9		; display buffer
tmp	res	2		; temporary value
flags	res	1		; signaling flags
bindex	res     1		; current index
tsec	res	1		; counter of tick seconds

B       equ     BANKED

	;; flags
LIGHT	equ	0
REFRESH	equ	1
LEADING	equ	2

        ;; main code
.main  code
isr:
	;; debug AID
	btg	LATB, 3, A

	;; handler for the CCP1IF interrupt
	btfss	PIR1, CCP1IF, A
	bra	isr_end
	bcf	PIR1, CCP1IF, A

	banksel 0
	;; save the current state of the buttons
	lfsr	FSR2, bstate
	movf	bindex, W, B
	addwf	FSR2L, F, A
	btfsc	STATUS, C, A
	incf	FSR2H, F, A
	movf	PORTA, W, A
	andlw	0x3F
	movwf	INDF2, A

	;; compute the new button index
	incf	bindex, F, B
	movlw	-10
	addwf	bindex, W, B
	btfsc	STATUS, C, A
	clrf	bindex, B

	;; do not count seconds if not needed
	btfss	flags, LIGHT, B
	bra	isr0_end

	;; handle the seconds
	decfsz	tsec, F, B
	bra	isr0_end
	movlw	250
	movwf	tsec, B

	;; decrease the timeout
	bsf	flags, REFRESH, B
	movlw	0
	decf	timeout+0, F, B
	subwfb	timeout+1, F, B

	;; check if the value is zero
	movf	timeout+0, W, B
	iorwf	timeout+1, W, B
	bnz	isr0_end

	;; timeout is zero
	bcf	LATB, 2, A
	bcf	flags, 0, B
	movf	setout+0, W, B
	movwf	timeout+0, B
	movf	setout+1, W, B
	movwf	timeout+1, B

isr0_end:
isr_end:
	retfie	FAST

	;; main code
start:
	;; initialize the ports as digital outputs with value 0
	movlb	0xF
	clrf	ANSELA, B	; ANSEL A/B/C are not in ACCESS BANK
	clrf	ANSELB, B
	clrf	ANSELC, B
	clrf	LATA, B
	movlw	0xff
	movwf	TRISA, B
	clrf	TRISB, B
	clrf	LATB, B
	clrf	TRISC, B
	clrf	LATC, B

	;; speed up the internal clock to 16MHz
	bsf	OSCCON, IRCF2, B
	delaycy	65536
	movlb	0x0

	;; initialize timeout
	movlw	LOW(65)
	movwf	setout+0, B
	movlw	HIGH(65)
	movwf	setout+1, B
	movff	setout+0, timeout+0
	movff	setout+1, timeout+1

 	;; initialize bstate
 	lfsr	FSR0, bstate
	movlw	10
main_l0:
	clrf	POSTINC0, A
	addlw	-1
	bnz	main_l0

	;; initialize dbuf
	call	seg_clear

	;; acs variables
	clrf	flags, B
	clrf	bindex, B
	movlw	250
	movwf	tsec, B

	;; initialize the periodicc TMR1
	;; period = 16000 * 0.25 nsec = 4msec
	clrf	T1CON, A	; no prescaler
	clrf	TMR1H, A
	clrf	TMR1L, A
	movlw	0x0B		; configure CCP for special event
	movwf	CCP1CON, A
	bcf	CCPTMRS, C1TSEL	; configure CCP for TMR1
	movlw	HIGH(16000-1)
	movwf	CCPR1H, A
	movlw	LOW(16000-1)
	movwf	CCPR1L, A	; set a period of 16000 * 0.25 nsec

	;; enable the interrupts
	bcf	PIR1, CCP1IF, A
	bsf	PIE1, CCP1IE, A
	bsf	INTCON, GIE, A
	bsf	INTCON, PEIE, A

	;; enable TMR1
	bsf	T1CON, TMR1ON, A

	;; initialize I2C support
	call	i2c_init
	call	seg_init

	;; write some numbers
	bcf	flags, 0, B
	bsf	flags, 1, B

main_l1:
	btfss	flags, 1, B
	bra	main_l2

	call	b16_d5

	;; convert the buffer to a proper
	;; matrix representation taking into account
	;; leading zeros
	bsf	flags, LEADING, B
	movf	dbuf+0, W, B	; most significant digit
	call	get_digit
	movwf	dbuf+0, B

	movf	dbuf+2, W, B
	call	get_digit
	movwf	dbuf+2, B

	movf	dbuf+6, W, B
	call	get_digit
	movwf	dbuf+6, B

	bcf	flags, LEADING, B
	movf	dbuf+8, W, B	; least significant digit
	call	get_digit
	movwf	dbuf+8, B

	call	seg_send_buf
	bcf	flags, 1, B

	;; switches
main_l2:
	;; if LIGHT do not read the user input
	btfsc	flags, LIGHT, B
	bra	main_l1

	;; read the buttons, save the old read
	movff	button+0, button+1
	call	get_switches

	;; check the button START
	btfss	button, 0, B
	bra	main_l3

	;; check if timeout is zero
	movf	timeout+0, W, B
	iorwf	timeout+1, W, B
	bz	main_l3

	;; set the start flags
	movff	timeout+0, setout+0
	movff	timeout+1, setout+1
	bsf	LATB, 2, A
	movlw	250
	movwf	tsec, B
	bsf	flags, REFRESH, B
	bsf	flags, LIGHT, B

main_l3:
	;; check the button PLUS
	btfss	button, 1, B
	bra	main_l4
	btfsc	button+1, 1, B
	bra	main_l4

	;; increase the seconds
	incf	timeout+0, F, B
	btfsc	STATUS, C, A
	incf	timeout+1, F, B
	bsf	flags, REFRESH, B

main_l4:
	;; check the button MINUS
	btfss	button, 2, B
	bra	main_l1
	btfsc	button+1, 2, B
	bra	main_l1

	;; decrease the seconds
	movlw	0
	decf	timeout+0, F, B
	btfss	STATUS, C, A
	decf	timeout+1, F, B
	bc	main_l5

	;; but not below 0
	clrf	timeout+0, B
	clrf	timeout+1, B
main_l5:
	bsf	flags, REFRESH, B
	bra	main_l1

seg_init:
	movlw	UPPER(seg_init_cmd)
	movwf	TBLPTRU, A
	movlw	HIGH(seg_init_cmd)
	movwf	TBLPTRH, A
	movlw	LOW(seg_init_cmd)
	movwf	TBLPTRL, A
	movlw	2
	call	i2c_send_tbl
	movlw	2
	call	i2c_send_tbl
	movlw	2
	call	i2c_send_tbl
	movlw	2
	bra	i2c_send_tbl
seg_init_cmd	db	0xE0,0x21,0xE0,0xA3,0xE0,0xE1,0xE0,0x81

seg_send_buf:
	call	i2c_start
	movlw	0xE0
	call	i2c_write
	movlw	0
	call	i2c_write
	movlw	9
	movwf	tmp, B
	lfsr	FSR0, dbuf
seg_send_l0:
	movf	POSTINC0, W, A
	call	i2c_write
	decf	tmp, F, B
	bnz	seg_send_l0
	bra	i2c_stop

seg_clear:
	movlw	9
	lfsr	FSR0, dbuf
seg_clear_l0:
	clrf	POSTINC0, A
	addlw	-1
	bnz	seg_clear_l0
	return

get_digit:
	andlw	0x0F
	bnz	get_digit_l0
	btfsc	flags, LEADING, B
	retlw	0
get_digit_l0:
	movwf	TBLPTRL, A
	movlw	HIGH(get_digit_l2)
	movwf	TBLPTRH, A
	movlw	UPPER(get_digit_l2)
	movwf	TBLPTRU, A
	movlw	LOW(get_digit_l2)
	addwf	TBLPTRL, F, A
	bnc	get_digit_l1
	incfsz	TBLPTRH, F, A
	incf	TBLPTRU, F, A
get_digit_l1:
	tblrd	*
	movf	TABLAT, W, A
	bcf	flags, LEADING, B
	return
get_digit_l2:
	db	0x3F,0x06,0x5B,0x4F
	db	0x66,0x6D,0x7D,0x07
	db	0x7F,0x6F,0x77,0x7C
	db	0x39,0x5E,0x79,0x71

	;; get_switches() - get the status of the switches
get_switches:
	movlw	10
	movwf	tmp, B
	lfsr	FSR0, bstate
	movlw	0xff
get_switches_l0:
	andwf	POSTINC0, W, A
	decfsz	tmp, F, B
	bra	get_switches_l0
	movwf	button, B
	return

	;; convert the timeout in BCD
b16_d5
        swapf   timeout+0, W, B	; partial ones sum in low byte
        addwf   timeout+0, W, B
        andlw   0x0f
        skpndc
        addlw 	0x16
        skpndc
        addlw  	0x06
        addlw   0x06
        skpdc
	addlw  	-0x06		; wmax=3:0

        btfsc	timeout+0, 4, B	; complete ones sum in low byte
        addlw   0x15+0x06
        skpdc
        addlw  	-0x06		; wmax=4:5
	movwf	dbuf+8, B	; save sum in dbuf+8
;
;     8+      4+     2+     1+     8+     4+    2+    1+
;    20
;   100      60     30     15+
;   ----------------------------------------------------
;   128      64     32     16      8      4     2     1
;
        swapf   timeout+1, W, B	; partial ones sum in high byte
        addwf   timeout+1, W, B
        andlw   0x0f
        skpndc
        addlw 	0x16
        skpndc
        addlw  	0x06
        addlw   0x06
        skpdc
	addlw  	-0x06		; wmax=3:0

	btfsc   timeout+1, 0, B	; complete ones sum in high byte
        addlw   0x05+0x06
        skpdc
        addlw  	-0x06		; wmax=3:5

        btfsc   timeout+1, 4, B
        addlw   0x15+0x06
        skpdc
        addlw  	-0x06		; wmax=5:0

	addlw	0x06		; include previous sum
	addwf	dbuf+8,w
        skpdc
        addlw  	-0x06		; wmax=9:5, ones sum ended

	movwf	dbuf+8, B
	movwf	dbuf+6, B
	swapf	dbuf+6, F, B
	movlw	0x0f
	andwf	dbuf+8, F, B	; save total ones sum in dbuf+8
	andwf	dbuf+6, F, B	; save partial tens sum in dbuf+6
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
	rrcf	timeout+1, W, B	; rotate right high byte once
	andlw	0x0f		; clear high nibble
	addlw	0x06		; adjust bcd
	skpdc
	addlw	-0x06		; wmax=1:5

	addlw	0x06		; include previous sum
	addwf	dbuf+6, W, B
        skpdc
        addlw  	-0x06		; wmax=2:4

        btfsc   timeout+0, 5, B
        addlw   0x03+0x06
        skpdc
        addlw  	-0x06		; wmax=2:7

        btfsc   timeout+0, 6, B
        addlw   0x06+0x06
        skpdc
        addlw  	-0x06		; wmax=3:3

        btfsc   timeout+0, 7, B
        addlw   0x12+0x06
        skpdc
        addlw  	-0x06		; wmax=4:5

        btfsc   timeout+1, 0, B
        addlw   0x25+0x06
        skpdc
        addlw  	-0x06		; wmax=7:0

        btfsc   timeout+1, 5, B
        addlw   0x09+0x06
        skpdc
        addlw  	-0x06		; wmax=7:9

        btfsc   timeout+1, 6, B
        addlw   0x08+0x06
        skpdc
        addlw  	-0x06		; wmax=8:7

        btfsc   timeout+1, 7, B
        addlw   0x06+0x06
        skpdc
        addlw  	-0x06		; wmax=9:3, tens sum ended

	movwf	dbuf+6		; save total tens sum in dbuf+6
	swapf	dbuf+6, W, B
	andlw	0x0f		; load partial hundreds sum in w
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
        addlw  	-0x06		; wmax=1:4

        btfsc   timeout+1, 5, B
        addlw   0x01+0x06
        skpdc
        addlw  	-0x06		; wmax=1:5

        btfsc   timeout+1, 6, B
        addlw   0x03+0x06
        skpdc
        addlw  	-0x06		; wmax=1:8

        btfsc   timeout+1, 7, B
        addlw   0x07+0x06
        skpdc
        addlw  	-0x06		; wmax=2:5, hundreds sum ended

	movwf	dbuf+2, B	; save total hundreds sum in dbuf+2
	swapf	dbuf+2, W, B
	movwf	dbuf+0, B	; save partial thousands sum in dbuf+0
	movlw	0x0f		; clear high nibble
	andwf	dbuf+6, F, B
	andwf	dbuf+2, F, B
	movlw	0x0f
	andwf	dbuf+0, F, B
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
	rrcf	timeout+1, W, B	; rotate right high byte twice
	movwf	tmp, B
	rrcf	tmp, W, B
	andlw	0x0f		; clear high nibble
	addlw	0x06		; adjust bcd
	skpdc
	addlw	-0x06		; wmax=1:5

	addlw	0x06		; include previous sum
	addwf	dbuf+0, W, B
	skpdc
	addlw	-0x06		; wmax=1:7

        btfsc   timeout+1, 6, B
        addlw   0x16+0x06
	skpdc
	addlw	-0x06		; wmax=3:3

        btfsc   timeout+1, 7, B
        addlw   0x32+0x06
	skpdc
	addlw	-0x06		; wmax=6:5, thousands sum ended

	movwf	dbuf+0, B	; save total thousands sum in dbuf+0
	movwf	tmp, B
	swapf	tmp, F, B	; save ten-thousands sum in tmp
	movlw	0x0f		; clear high nibble
	andwf	dbuf+0, F, B
	andwf	tmp, F, B
	return

	end
