        include "config.inc"

        global  i2c_init, i2c_start, i2c_restart, i2c_stop, i2c_write
        global  i2c_read_ack, i2c_read_nack, i2c_send_tbl

#define SPEED(x) (FOSC/1000/x)/4-1

.i2c    code

i2c_init:
        ;; RB0 and RB1 should be set as inputs
        bsf     TRISB, 0, A
        bsf     TRISB, 1, A

        ;; disable slew rate and enable smbus
        movlw   0xC0
        movwf   SSP1STAT, A

        ;; I2C master mode
        movlw   8 << SSPM0
        movwf   SSP1CON1, A

        ;; clear any error in SSP1CON2
        clrf    SSP1CON2, A
        clrf    SSP1CON3, A

        ;; set the baud rate to 100kHz
        movlw   SPEED(100)
        movwf   SSP1ADD, A

        ;; disable interrupts and enable I2C, CKP, I2C Master
        bcf     PIE1, SSPIE, A
        bcf     PIE2, BCLIE, A

        bsf     SSP1CON1, SSPEN, A
        return

i2c_wait_idle:
        btfsc   SSP1STAT, R_NOT_W, A
        bra     i2c_wait_idle
        btfsc   SSP1CON2, SEN, A
        bra     i2c_wait_idle
        btfsc   SSP1CON2, RSEN, A
        bra     i2c_wait_idle
        btfsc   SSP1CON2, PEN, A
        bra     i2c_wait_idle
        btfsc   SSP1CON2, RCEN, A
        bra     i2c_wait_idle
        btfsc   SSP1CON2, ACKEN, A
        bra     i2c_wait_idle
        bcf     PIR1, SSPIF, A
        return

i2c_wait_completed:
        btfss   PIR1, SSPIF, A
        bra     i2c_wait_completed
        bcf     PIR1, SSPIF, A
        return

i2c_start:
        call    i2c_wait_idle
        bsf     SSP1CON2, SEN, A
        bra     i2c_wait_completed

i2c_restart:
        call    i2c_wait_idle
        bsf     SSP1CON2, RSEN, A
        bra     i2c_wait_completed

i2c_stop:
        call    i2c_wait_idle
        bsf     SSP1CON2, PEN, A
        bsf     SSP1CON2, ACKEN, A
        bra     i2c_wait_completed

        ;; i2c_write() - writes a byte into the bus
        ;; @W: byte to write
        ;;
        ;; Return: carry flag set if !ACK
i2c_write:
        call    i2c_wait_idle
        movwf   SSP1BUF, A
        call    i2c_wait_completed
        bcf     STATUS, C, A
        btfsc   SSP1CON2, ACKSTAT, A
        bsf     STATUS, C, A
        return

        ;; i2c_send_tbl() - send data from table
        ;; @TBLPTRU: upper address of data
        ;; @TBLPTRH: higher address of data
        ;; @TBLPTRL: lower add of data
        ;; @W: number of bytes to send
        ;;
        ;; Send at most W bytes of data but stop early
        ;; if we don't receive an ACK (last byte)
        ;;
        ;; Return: no value
i2c_send_tbl:
        call    i2c_start
i2c_send_tbl_loop:
        tblrd   *+
        call    i2c_wait_idle
        movff   TABLAT, SSP1BUF
        call    i2c_wait_completed
        btfsc   SSP1CON2, ACKSTAT, A
        bra     i2c_stop
        addlw   -1
        bnz     i2c_send_tbl_loop
        bra     i2c_stop

        ;; i2c_read_nack() - read a byte without ACK
        ;;
        ;; Read a byte without sending the ACK to inform
        ;; the sender it was the last byte needed.
        ;;
        ;; Return: value read in W
i2c_read_nack:
        call    i2c_wait_idle
        bsf     SSP1CON2, RCEN, A
        call    i2c_wait_completed
        movf    SSPBUF, W, A
        bsf     SSP1CON2, ACKDT, A
        bsf     SSP1CON2, ACKEN, A
        bra     i2c_wait_completed

        ;; i2c_read_ack() - read a byte with ACK
        ;;
        ;; Read a byte and send the ACK to inform
        ;; the sender we need more data.
        ;;
        ;; Return: value read in W
i2c_read_ack:
        call    i2c_wait_idle
        bsf     SSP1CON2, RCEN, A
        call    i2c_wait_completed
        movf    SSPBUF, W, A
        bcf     SSP1CON2, ACKDT, A
        bsf     SSP1CON2, ACKEN, A
        bra     i2c_wait_completed

        end
