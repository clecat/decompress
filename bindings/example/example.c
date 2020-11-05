#include <stdlib.h>
#include <caml/callback.h>
#include "decompress.h"

int main()
{
  char *i = malloc(0x1000);
  char *o = malloc(0x1000);

  int a = decompress_deflate(i, 0x1000, o, 0x1000, 2);
  int b = decompress_inflate(o, 0x1000, i, 0x1000);

  return (0);
}
