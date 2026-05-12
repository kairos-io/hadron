.PHONY: all clean
all: hadron-splash hadron-splash-fb

CFLAGS_COMMON = -Os -std=c99 -Wall -Wextra -Wpedantic \
	-fno-asynchronous-unwind-tables -fno-unwind-tables -fno-stack-protector \
	-ffunction-sections -fdata-sections -fno-plt -fno-pie -no-pie -flto \
	-Wl,--gc-sections -Wl,--build-id=none -Wl,-z,noseparate-code -Wl,-z,norelro \
	-Wl,--hash-style=gnu -s

hadron-splash: main.c
	@gcc $(CFLAGS_COMMON) -o $@ $< -lm

hadron-splash-fb: fb.c
	@gcc $(CFLAGS_COMMON) -o $@ $< -lm

clean:
	@rm -f hadron-splash hadron-splash-fb *.o
