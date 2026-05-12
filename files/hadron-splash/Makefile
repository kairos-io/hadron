.PHONY: all clean
all: hadron

hadron: main.c
	@cc -Os -std=c99 -Wall -Wextra -Wpedantic \
		-fno-asynchronous-unwind-tables -fno-unwind-tables -fno-stack-protector \
		-ffunction-sections -fdata-sections -fno-plt -fno-pie -no-pie -flto \
		-Wl,--gc-sections -Wl,--build-id=none -Wl,-z,noseparate-code -Wl,-z,norelro \
		-Wl,--hash-style=gnu -s -o $@ $< -lm
	@strip -R .eh_frame -R .eh_frame_hdr -R .sframe -R .note.ABI-tag -R .note.gnu.property -R .comment $@ 2>/dev/null || true
	@objcopy --strip-section-headers $@ 2>/dev/null || true
	@echo "$@: $$(stat -c %s $@) bytes"

clean:
	@rm -f hadron *.o
