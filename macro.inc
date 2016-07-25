        ;; useful macros
ltab    macro   addr
        movlw   UPPER(addr)
        movwf   TBLPTRU, A
        movlw   HIGH(addr)
        movwf   TBLPTRH, A
        movlw   LOW(addr)
        movwf   TBLPTRL, A
        endm

ltabw   macro   addr
        movwf   TBLPTRL, A
        movlw   HIGH(addr)
        movwf   TBLPTRH, A
        movlw   UPPER(addr)
        movwf   TBLPTRU, A
        movlw   LOW(addr)
        addwf   TBLPTRL, F, A
        movlw   0
        addwfc  TBLPTRH, F, A
        addwfc  TBLPTRU, F, A
        endm
