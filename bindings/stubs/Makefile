.PHONY: all clean
all: libdecompress.a

CC ?= cc

PACKAGES=decompress.zl,checkseum,checkseum.c,ctypes.stubs,ctypes.foreign
OBJS= bindings.o decompress.o

libdecompress.a: $(OBJS)
	ar r $@ $^

bindings.o: decompress_bindings.ml $(APPLY_BINDINGS) $(GEN_DECOMPRESS_BINDINGS)
	ocamlfind opt -g -verbose -cclib -L/usr/lib/x86_64-linux-gnu/ -I ../lib/ -o $@ -linkpkg -linkall -output-complete-obj -package $(PACKAGES) $^

%.o: %.c
	$(CC) -g -I $(shell ocamlfind query ctypes) -I $(shell ocamlopt -where) -c $^

clean:
	$(RM) $(OBJS) libdecompress.a
