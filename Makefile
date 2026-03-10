.PHONY : all clean fclean

TARGET     = asm-server

NASM       = nasm
LD         = ld

SRC        = webserver.s
OBJ        = $(SRC:%.s=%.o)

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) -o $@ $^
%.o: %.s
	$(NASM) -f elf64 -o $@ $^

clean:
	rm -f $(OBJ)
fclean: clean
	rm -f $(TARGET)
