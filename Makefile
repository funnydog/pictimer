LINKSCRIPT = /usr/share/gputils/lkr/18f25k50_g.lkr
OBJECTS = delay.o i2c.o main.o
OUTPUT = timer.hex

all: $(OUTPUT)

$(OUTPUT): $(OBJECTS)
	gplink -m -c -s $(LINKSCRIPT) -o $@ $^

%.o: %.asm
	gpasm -p18f25k50 -w2 -c -o $@ $<

# explicit dependencies
delay.o: config.inc
usart.o: config.inc
main.o: config.inc usart.inc delay.inc

.PHONY = clean program sim

clean:
	rm -f *.o *.hex *.cod *.map *.lst *.cof *~

program: $(OUTPUT)
	pk2cmd -R -P -M -Y -F $<

sim: $(OUTPUT)
	gpsim sim.stc
