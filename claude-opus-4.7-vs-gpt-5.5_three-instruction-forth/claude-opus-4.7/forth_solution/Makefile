# Makefile — Three-Instruction Forth, macOS arm64
#
# Builds boot.s into a Mach-O binary using the system /usr/bin/as and
# /usr/bin/ld. Links against libSystem (per spec — read/write/exit only)
# because modern macOS will SIGKILL fully-static binaries.

AS      := /usr/bin/as
LD      := /usr/bin/ld
CODESIGN := /usr/bin/codesign
SDK     := $(shell xcrun --show-sdk-path)
ARCH    := arm64
MACMIN  := 11.0

ASFLAGS := -arch $(ARCH)
LDFLAGS := -arch $(ARCH) -macos_version_min $(MACMIN) -lSystem -syslibroot $(SDK) -e _main

BIN     := forth
OBJ     := boot.o

.PHONY: all run test clean

all: $(BIN)

$(BIN): $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $<
	$(CODESIGN) -s - $@

$(OBJ): boot.s
	$(AS) $(ASFLAGS) -o $@ $<

run: $(BIN)
	cat core.f test.f | ./$(BIN)

test: $(BIN)
	@cat core.f test.f | ./$(BIN); \
	  status=$$?; \
	  if [ $$status -eq 0 ]; then \
	    echo ""; echo "OK — exit 0"; \
	  else \
	    echo ""; echo "FAIL — exit $$status"; exit $$status; \
	  fi

clean:
	rm -f $(BIN) $(OBJ)
