---
layout: post
title: "picoCTF 2017 weirderRSA Writeup"
date: 2017-04-09 22:00:00 -0700
comments: true
published: true
tags: ['ctf', 'writeup', 'crypto', 'rsa']
mathjax: true
---
picoCTF 2017 was happening over the last two weeks, and while I didn't have time to play it, a friend messaged me asking for help on one of the "master" level problems. The problem was a fun cryptography problem related to RSA, and I heard that some people ended up solving the problem using brute force, so I decided to writeup my solution which doesn't require brute force. Note that there's nothing wrong with the brute force solution, and you probably would have solved the problem faster, but it's good practice to be able to do it with just number theory.

<!-- more -->

Here was the problem description:
```
Another message encrypted with RSA. It looks like some parameters are missing. Can you still decrypt it?
```

A few hints were provided:
```
Is there some way to create a multiple of p given the values you have?
Fermat's Little Theorem may be helpful.
```

Here are the provided RSA parameters, as well as the encrypted message $c$:
```
e = 65537
n = 551504906448961847141690415172108060028728303241409233555695098354559944134593608349928135804830998592132110248539199471080424828431558863560289446722435352638365009233192053427739540819371609958014315243749107802424381558044339319969305152016580632977089138029197496120537936093909331580951370236220987003013
dp = 11830038111134559585647595089660079959437934096133759102294626765549623265660232459679672150751523484215314838435592395437758168739238085557609083462380613

c = 418572163495460705091994402313468259824845152046819051708475973278685439488218787721608798128772047429018094097494688211258770586158227367592079338748634678836934643602701977245535903228577069635940900201087759467891714571538138574420185845350371745237794514198783443249846917698316091319797744417823562800249
```

Note that instead of just $e$ and $n$ (where $n = p * q$) and $p$ and $q$ are large primes), $dp$ is provided. $dp$ is the standard name for $d \bmod (p - 1)$, which is used to speed up RSA calculations using the Chinese Remainder Theorm (CRT). The details of how RSA is done with CRT isn't relevant here, the only fact we need is that $e * dp \equiv 1 \pmod{p - 1}$. We know this because we can rewrite $d \equiv dp \pmod{p - 1}$ as $d = dp + k(p - 1)$ for some integer $k$ and we know $e * d \equiv 1 \pmod{(p - 1)(q - 1)}$ by definition, thus

$$
\begin{equation}
\begin{split}
e * d &= e(dp + k(p - 1)) \\\\\\
&= e * dp + e * k(p - 1) \\\\\\
&\equiv 1 \pmod{(p - 1)(q - 1)} \\\\\\
\end{split}
\end{equation}
$$

We can rewrite this as

$$e * dp + e * k(p - 1) = 1 + j(p - 1)(q - 1)$$

for some integer $j$. We can rearrange this to get $e * dp = 1 + (p - 1)(e * k + j(q - 1))$. Thus, $e * dp \equiv 1 \pmod{p - 1}$. We will come back to why this equation is important.

After reading the first hint about finding a multiple of $p$, I immediately knew how the end of the problem would look once I had that multiple. If we can find a multiple of $p$ such as $a * p$ for some positive integer $a > 1$ and $gcd(a, q) = 1$, then we can do $gcd(a * p, n) = gcd(a * p, p * q)$ to give us $p$ (because the only shared factor between $a * p$ and $p * q$ should be $p$). Once we have $p$, we can just do $n / p$ to find $q$ and completely factorize $n$. Given the factorization of $n$, we can calculate the decryption exponent $d$ and then decrypt $c$ by doing $c^d \bmod n$. So knowing that, I began looking at ways to create a multiple of $p$ using Fermat's Little Theorem. Fermat's Little Theorem is $a^{p - 1} \equiv 1 \pmod{p}$,  and from here I immediately realized $a^{p - 1} - 1$ is a multiple of $p$. While I couldn't come up with this exact equation, this general idea was how I came up with the solution.

Now, we can take the congruence from earlier, $e * dp \equiv 1 \pmod{p - 1}$, and rewrite it as $e * dp = 1 + k(p - 1)$ for some integer $k$. After looking at this, I saw a way we might be able to get a $(p - 1)$ into the exponent of an equation so that we could apply Fermat's Little Theorem to it. If we raise some integer $a$ to $e * dp$, we would have

$$a^{e * dp} = a^{1 + k(p - 1)} = a^1 * a^{k(p - 1)} = a(a^k)^{p - 1}$$

If we take this value $\bmod p$, then we can apply Fermat's Little Theorem to it: $a(a^k)^{p - 1} \equiv a \pmod{p}$. Since we started with $a^{e * dp}$ on the left hand side of our original congruence and we're left with $a$ on the right hand side,  we now know that $a^{e * dp} \equiv a \pmod{p}$. We can rewrite that as $a^{e * dp} - a \equiv 0 \pmod{p}$. The right hand side of this congruence is zero, which means the value on the left hand side is a multiple of $p$. Furthermore, all the values on the left hand side of the congruence are known, except for $a$, but since $a$ is any integer greater than one, we can choose anything we want, like two. Thus, $2^{e * dp} - 2$ is a multiple of $p$.

The only remaining problem here is if you plug $2^{e * dp}$ into Sage or any other library, it probably won't be able to compute it because of how large the exponent is. Luckily, $2^{e * dp} \bmod n$ is also a multiple of $p$, and we can use that instead. To see why, we can take the congruence $a * p \equiv 0 \pmod{p}$ (for some integer $a$) and subtract $b * n$ (for some positive integer $b$) from the left side (which is the same as doing $\pmod n$), and we get

$$a * p - b * n = a * p - b(p * q) = p(a - b * q) \equiv 0 \pmod p$$

So taking our original expression $\bmod n$ preserves the factor of $p$ in the expression, so it's still a multiple of p.

Thus, we can solve the problem in Sage as follows (note that the casts to `int`s are important in Sage):
```
sage: p = int(gcd(pow(2, e * dp, n) - 2, n)); p
21882732364928750538091629675163778162621616902577425071608324988253617272412493782388559800841168348434069674472295196720416514385081750301694228136439127L
sage: q = n / p; q
25202744211817605397350328299983891415826580931890036611534540754079335081397262505214808536988764318124618606869256238502481259725033526700937302921554819
sage: d = inverse_mod(e, (p - 1) * (q - 1)); d
34535852054054036966438766862479690531423485306052207066429233618369989635295667617805286621954413815434184971237695876059539855286069206342240686777680920609564888947098210601853114202918429853613788197596527012265264741745540817155411813474104528185518260915438910819103674793733905258024133003488830258529
sage: m = int(pow(c, d, n)); m
3670434958110785066911905751469631231338751225710158680692616521935747246580686931770254296884504612059517L
sage: hex(m)[2:-1].decode('hex')
'flag{wow_leaking_dp_breaks_rsa?_44704215209}'
```

And indeed, leaking $dp$ breaks RSA. Definitely a very fun problem.
