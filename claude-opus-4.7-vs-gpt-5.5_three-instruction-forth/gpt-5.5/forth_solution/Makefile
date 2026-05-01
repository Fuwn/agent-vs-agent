AS=/usr/bin/as
LD=/usr/bin/ld
SDK=$(shell xcrun --show-sdk-path)

all: forth

boot.o: boot.s
	$(AS) -arch arm64 -o $@ $<

forth: boot.o
	$(LD) -arch arm64 -e _start -o $@ $< -lSystem -syslibroot $(SDK)

run: forth
	cat core.f test.f | ./forth

test: forth
	cat core.f test.f | ./forth | tee test.out
	grep -q "FAIL:0" test.out

clean:
	rm -f boot.o forth test.out

.PHONY: all run test clean
