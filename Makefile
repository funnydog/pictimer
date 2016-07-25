LINKSCRIPT = /usr/share/gputils/lkr/18f25k50_g.lkr
OBJECTS = delay.o i2c.o main.o
OUTPUT = timer.hex

all: $(OUTPUT)

$(OUTPUT): $(OBJECTS)
	gplink -m -c -s $(LINKSCRIPT) -o $@ $^

%.o: %.asm
	gpasm -w2 -c -S2 -o $@ $<

# explicit dependencies
delay.o: config.inc
i2c.o: config.inc
main.o: config.inc delay.inc i2c.inc macro.inc

.PHONY = clean program sim

clean:
	rm -f *.o *.hex *.cod *.map *.lst *.cof *~

program: $(OUTPUT)
	pk2cmd -R -P -M -Y -F $<

sim: $(OUTPUT)
	gpsim sim.stc
