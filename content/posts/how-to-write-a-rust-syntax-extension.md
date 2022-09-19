---
layout: post
title: "How to write a Rust syntax extension"
date: 2015-05-02 01:34:29 -0400
comments: true
published: true
tags: [rust, syntax extension]
---

While I was working on my [ggp-rs](https://github.com/gsingh93/ggp-rs) project last week, I was having some trouble tracking down a strange bug that was happening. The relevant code was related to the [unification, substitution, and general statement proving](http://logic.stanford.edu/ggp/chapters/chapter_13.html) algorithms, which is a non-trivial piece of code to write, read, and debug. I started to put `println!` statements in various functions, sometimes just to see if the function was entered, and sometimes to see the value of some variables. After spending about half an hour on this bug, I got fed up with the code, took a step back, and started thinking of an easier, more structured approach to debugging the code. I realized that putting print statements in the code to trace execution is a common debugging practice used by myself and other developers all the time, and it might be possible to make this more convenient with the help of Rust's syntax extensions/compiler plugins.

<!-- more -->

Syntax extensions are a cool feature that allow you to modify the AST at compile time, so you can generate your own code or modify existing code. After realizing this, I took a break from `ggp-rs` and wrote [trace](https://github.com/gsingh93/trace), a syntax extension for tracing the execution of programs. With `trace`, I was able to track my bug in about 10 minutes. Writing this syntax extension was a lot of fun, but also very challenging due to the lack of documentation on syntax extensions. The reason for the lack of documentation is due to the fact that syntax extensions are not stable and their API is very rough around the edges. However, writing this plugin made me realize how powerful syntax extensions are and how many useful projects could be made if there was some good documentation on how to use them. In this post, I'm going to try to cover the basics of how to write your own syntax extensions.

Note that because syntax extensions are unstable, these plugins will only work on the nightly compiler (unless you use something like [rust-syntex](https://github.com/erickt/rust-syntex), which I haven't gotten a chance to try out). However, I still think learning how to use them now is worthwhile, as more people writing them will help them become stable faster, there will be more good feedback during the stabilization process, and because it's a lot of fun.

The following information is valid as of 5/04/15 and Rust 1.0, and I'll do my best to keep it updated.

## Types of Syntax Extensions

There are six types of [SyntaxExtension](http://doc.rust-lang.org/syntax/ext/base/enum.SyntaxExtension.html)s you can define:

### Decorator

A `Decorator` is an attribute that is attached to an item and creates new items without affecting the original item. For example, adding `#[derive(..)]` on a struct doesn't modify the struct itself but adds a new `ItemImpl` to the AST. Note that when I say "item", I'm referring to the variants of the [Item_](http://doc.rust-lang.org/syntax/ast/enum.Item_.html) enum. You can generally think of these things at top-level constructs, i.e. functions, mods, imports, etc.

### Modifier

A `Modifier` is an attribute that modifies and replaces an item. For example, adding `#[trace]` (from my `trace` syntax extension) to a function will replace the original function with a new, modified version.

### MultiModifier

A `MultiModifer` is the same thing as a modifier, but it can be applied to methods inside of traits and `impl`s as well as top-level items. Hopefully `MultiModifier` and `Modifier` will get merged before the API is stabilized, as I don't really see the point of having both.


### NormalTT

A `NormalTT` looks like a regular macro, but has all the power of a compiler plugin. An example of a `NormalTT` is the [concat!](http://doc.rust-lang.org/std/macro.concat!.html) macro.

### IdentTT

An `IdentTT` is the same as a `NormalTT` except there is an identifier after the macro name. The only example of an `IdentTT` I've seen is in [rust-peg](https://github.com/kevinmehall/rust-peg), where the extra identifier is used as the name of the module that will be generated.

### MacroRulesTT

You don't need to worry about this variant. It's used for the regular types of macros you'd define with `macro_rules!`.

## Registering a Syntax Extension

Now that you know the different types of syntax extensions you can write, let's actually register one. Create a new Cargo project called "extension" (it's often said that there are only two hard problems in computer science, cache invalidation and naming things).

Add the following code to `lib.rs`:
``` rust lib.rs
#![feature(plugin_registrar, rustc_private)]

extern crate syntax;
extern crate rustc;

use rustc::plugin::Registry;

use syntax::ptr::P;
use syntax::ast::{Item, MetaItem};
use syntax::ext::base::ExtCtxt;
use syntax::codemap::Span;
use syntax::ext::base::SyntaxExtension::Modifier;
use syntax::parse::token::intern;

#[plugin_registrar]
pub fn registrar(reg: &mut Registry) {
    reg.register_syntax_extension(intern("extension"), Modifier(Box::new(expand)));
}

fn expand(_: &mut ExtCtxt, _: Span, _: &MetaItem, item: P<Item>) -> P<Item> {
    println!("Hello world!");
    return item;
}
```

Here's an example `Cargo.toml`:
``` rust Cargo.toml
[package]
name = "extension"
version = "0.0.1"

[lib]
name = "extension"
plugin = true
```

In the `lib` section, we add `plugin = true`. This makes sure that a `dylib` is built instead of an `rlib` when you run `cargo build`, as all syntax extensions need to be dynamically linked.

In the code, we declare a function that will be used to register our extension and add the `#[plugin_registrar]` attribute to it (note this requires the `plugin_registrar` feature to be enabled). When your syntax extension is loaded (we'll get to loading it later), this function is called. We then call `register_syntax_extension` and pass in a [Name](http://doc.rust-lang.org/syntax/ast/struct.Name.html) (which is just an [interned string](https://en.wikipedia.org/wiki/String_interning), although I don't see why the API couldn't just take a normal `&str`) and the correct `SyntaxExtension` variant, which contains a boxed callback to the function that will do the actual work. In this case we use a `Modifier`, and our callback just prints to standard out and returns the original item without any modifications. We'll come back to what the other arguments for the `expand` function are later. Once you have this extension registered, you can use the `#[extension]` attribute on any item. If you want to use on a parent item, you can use `#![extension]`. This is useful for using an attribute on a `mod` from inside the `mod` itself.

The only other thing to note is that if you're registering a `NormalTT` extension, you should use the `register_macro` function instead of the `register_syntax_extension` function.

If you want to find out what interface of the callback looks like for a particular type of syntax extension, just click on the trait name inside the `Box` for that variant on the [SyntaxExtension](http://doc.rust-lang.org/syntax/ext/base/enum.SyntaxExtension.html) page. For example, the `Modifier` callback implements the [ItemModifier](http://doc.rust-lang.org/syntax/ext/base/trait.ItemModifier.html) trait. Because this is a trait, note that you can use structs that implement this trait instead of callbacks if you need to.

## Loading a Syntax Extension

Loading our syntax extension is also straightforward:
``` rust example.rs
#![feature(plugin, custom_attribute)]
#![plugin(extension)]

#[extension]
fn main() {
}
```

Put this in `examples/example.rs` and then run `cargo run --example example.rs`. You should see the text "Hello World" appear in during the compilation. Congratulations, you just wrote your first syntax extension!

## Creating new AST nodes

Let's try doing something more interesting, like creating new AST nodes.

Before I show an example of creating a new node, let's quickly talk about what an AST node looks like. You can find all the AST nodes in the [syntax::ast](http://doc.rust-lang.org/syntax/ast/index.html) module. For example, take a look at the [Item](http://doc.rust-lang.org/syntax/ast/struct.Item.html) node. You can find the name of the item (i.e. the function name if this item is a function) and some other metadata about the node, like what attributes (attributes are things like `#[...]`) are attached to the node, what the span is, etc. The span represents the position of the code in the file and is used for error reporting. We'll come back to how to effectively use that in a later section. The actual item itself is stored in the `node` field as an `Item_`. This enum contains the different types of items, like `ItemMod`, `ItemFn`, etc. This pattern of splitting a node into `Node` and `Node_` is fairly common, so it's useful to understand it early on.

Another thing about AST nodes is they're often wrapped in `P` pointers. You can read more about this type of pointer in the [module documentation](http://doc.rust-lang.org/syntax/ptr/index.html), but you can just think of these as any other pointer type (i.e. `Box`, `Rc`, etc.).

To create a new node, you can use the [ExtCtxt](http://doc.rust-lang.org/syntax/ext/base/struct.ExtCtxt.html) struct, which implements the [AstBuilder](http://doc.rust-lang.org/syntax/ext/build/trait.AstBuilder.html) trait. You should be able to find a method in that trait to make whatever AST node you want. There are also various `quote_*` macros that you can use to create nodes from actual code. These macros don't appear in the documentation, but you can figure out what's available by looking at what expansion functions exist in [this module](http://doc.rust-lang.org/syntax/ext/quote/index.html). Note that there might be a time where you want to create some node and the current API doesn't offer any helper methods for it. In that case, you'll have to create that node manually, which isn't hard, but is very tedious. There's a project called [aster](https://github.com/erickt/rust-aster) that's supposed to make this easier, but I haven't tried it out yet.

Let's modify our `expand` function to compute the sum of two plus two, print the result, and return it. There are multiple ways to do this, but I'll only show two of them. This first method is longer, but it'll show you more about working with AST nodes. The second method is how I'd actually do it, and it'll show how to use variables declared outside `quote_*` macros inside the macros themselves.

Here's method one:

``` rust lib.rs
#![feature(quote, plugin_registrar, rustc_private)]

extern crate syntax;
extern crate rustc;

use rustc::plugin::Registry;

use syntax::ptr::P;
use syntax::ast::{Item, MetaItem, ItemFn, Ident};
use syntax::ext::base::ExtCtxt;
use syntax::codemap::Span;
use syntax::ext::base::SyntaxExtension::Modifier;
use syntax::parse::token::intern;
use syntax::ext::build::AstBuilder;

use syntax::codemap;

#[plugin_registrar]
pub fn registrar(reg: &mut Registry) {
    reg.register_syntax_extension(intern("extension"), Modifier(Box::new(expand)));
}

fn expand(cx: &mut ExtCtxt, _: Span, _: &MetaItem, item: P<Item>) -> P<Item> {
    if let ItemFn(..) = item.node {
        let expr = quote_expr!(cx,
            {
                let sum = 2 + 2;
                println!("{}", sum);
                sum
            });
        let new_block = cx.block_expr(expr);
        let inputs = vec![];
        let u32_ident = Ident::new(intern("u32"));
        let ret_type = cx.ty_path(cx.path_ident(codemap::DUMMY_SP, u32_ident));
        cx.item_fn(codemap::DUMMY_SP, item.ident, inputs, ret_type, new_block)
    } else {
        item.clone()
    }
}
```

Change `example.rs` to look like this:
``` rust example.rs
#![feature(plugin, custom_attribute)]
#![plugin(extension)]

fn main() {
    foo();
}

#[extension]
fn foo() {
}
```

We use the `quote_expr!` macro which returns a `P<Expr>`. We can then use this expression to create a new `Block`. We create an empty vector for the inputs, and use a `u32` for the return type. We then supply all of these variables to the `ExtCtxt` to create a new `P<Item>`, which is really an `ItemFn`.

Note that I didn't really know the methods for creating the `u32` return type of the top of my head. These types of things aren't worth learning/memorizing. If you ever need to make a type, first look at the `AstBuilder` methods to find what returns the type you want, see what types of arguments the method requires, and if you need to make any more nodes to pass as arguments, repeat the process.

Here's the second way of doing this:
``` rust lib.rs
fn expand(cx: &mut ExtCtxt, _: Span, _: &MetaItem, item: P<Item>) -> P<Item> {
    if let ItemFn(..) = item.node {
        quote_item!(cx,
            fn foo() -> u32 {
                let sum = 2 + 2;
                println!("{}", sum);
                sum
            }
        ).unwrap()
    } else {
        item.clone()
    }
}
```

Here we use `quote_item!` to create a `P<Item>` directly, instead of creating the inner block expression and constructing a function from that. Note that this macro returns an `Option` which is `None` if the parsing fails, unlike `quote_expr!` which always returns an expression.

This gets the job done, but the problem with this is that we can only use this macro with functions that have the name `foo`. Instead, we can dynamically choose the name by getting the name from the item:
``` rust lib.rs
fn expand(cx: &mut ExtCtxt, _: Span, _: &MetaItem, item: P<Item>) -> P<Item> {
    if let ItemFn(..) = item.node {
        let name = item.ident;
        quote_item!(cx,
            fn $name() -> u32 {
                let sum = 2 + 2;
                println!("{}", sum);
                sum
            }
        ).unwrap()
    } else {
        item.clone()
    }
}
```

Here we get the `Name` from the item and use it inside the macro by prepending a dollar sign to it. Any type that implements the [ToTokens](http://doc.rust-lang.org/syntax/ext/quote/rt/trait.ToTokens.html) trait can be used like this. Note that it doesn't work with struct fields or methods, i.e. `$foo.bar` or `$foo.bar()` won't work. You have to assign the result of those expressions to a variable outside the macro, and then use that variable inside the macro.

## Token Trees

I mentioned the `ToTokens` trait in the last section, which returns a vector of `TokenTree`s representing the struct it was implemented on. But what is a `TokenTree`?

Imagine we call a function `foo` like this: `foo(a, b, c)`. The first stage of a compiler is lexical analysis, where text like this is turned into tokens. The tokens for the arguments of this function (so not including the name or the parenthesis) would looks like this:
``` rust
[TtToken(Span { lo: BytePos(0), hi: BytePos(0), expn_id: ExpnId(4294967295) }, Ident(a#0, Plain)),
 TtToken(Span { lo: BytePos(0), hi: BytePos(0), expn_id: ExpnId(4294967295) }, Comma),
 TtToken(Span { lo: BytePos(0), hi: BytePos(0), expn_id: ExpnId(4294967295) }, Ident(b#0, Plain)),
 TtToken(Span { lo: BytePos(0), hi: BytePos(0), expn_id: ExpnId(4294967295) }, Comma),
 TtToken(Span { lo: BytePos(0), hi: BytePos(0), expn_id: ExpnId(4294967295) }, Ident(c#0, Plain))]
```

It's a bit verbose, but you can see that it concretely describes the text that represents the arguments and includes things we don't normally think about, like commas.

Now let's say we want to write a syntax extension that prints out the values of all the arguments when a function is called. We can figure out how many arguments the function has easily, so we can construct the appropriate format string to pass to `println!`. But the number of arguments `println!` takes depends on the number of arguments the function takes, and this varies, so it's not immediately obvious how we can do this.

The solution here is to use `TokenTree`s. Because `TokenTree`s are a direct representation of the code, we can convert them directly into code. That's why all dollar-prepended variables in an `quote` macro need to implement the `ToToken`s trait, so there's an easy way to turn it into code. That means if we can construct a token tree that looks like `a, b, c`, we can plug that in as the second argument of `println!` and it will expand to valid code. Here's a full example:

``` rust lib.rs
#![feature(quote, plugin_registrar, rustc_private, collections)]

extern crate syntax;
extern crate rustc;

use rustc::plugin::Registry;

use syntax::ptr::P;
use syntax::ast::{self, FnDecl, Item, MetaItem, ItemFn, Ident, TokenTree, TtToken};
use syntax::codemap::{self, Span};
use syntax::ext::base::ExtCtxt;
use syntax::ext::base::SyntaxExtension::Modifier;
use syntax::ext::build::AstBuilder;
use syntax::ext::quote::rt::ToTokens;
use syntax::parse::token::{self, intern};

use std::slice::SliceConcatExt;

#[plugin_registrar]
pub fn registrar(reg: &mut Registry) {
    reg.register_syntax_extension(intern("extension"), Modifier(Box::new(expand)));
}

fn expand(cx: &mut ExtCtxt, _: Span, _: &MetaItem, item: P<Item>) -> P<Item> {
    if let ItemFn(ref decl, style, abi, ref generics, ref block) = item.node {
        let idents = arg_idents(decl);
        let args: Vec<TokenTree> = idents
            .iter()
            .map(|ident| vec![token::Ident((*ident).clone(), token::Plain)])
            .collect::<Vec<_>>()
            .connect(&token::Comma)
            .into_iter()
            .map(|t| TtToken(codemap::DUMMY_SP, t))
            .collect();

        println!("{:?}", args);
        let format_str = idents.iter().map(|_| "{}".to_string()).collect::<Vec<_>>().connect(" ");
        let expr = quote_expr!(cx,
            {
                println!($format_str, $args);
                $block
            }
        );
        let new_block = cx.block_expr(expr);
        let new_item = ItemFn(decl.clone(), style, abi, generics.clone(), new_block);
        cx.item(item.span, item.ident, item.attrs.clone(), new_item)
    } else {
        item.clone()
    }
}

fn arg_idents(decl: &FnDecl) -> Vec<Ident> {
    fn extract_idents(pat: &ast::Pat_, idents: &mut Vec<Ident>) {
        match pat {
            &ast::PatWild(_) | &ast::PatMac(_) | &ast::PatEnum(_, None) | &ast::PatLit(_)
                | &ast::PatRange(..) | &ast::PatQPath(..) => (),
            &ast::PatIdent(_, sp, _) => if sp.node.as_str() != "self" { idents.push(sp.node) },
            &ast::PatEnum(_, Some(ref v)) | &ast::PatTup(ref v) => {
                for p in v {
                    extract_idents(&p.node, idents);
                }
            }
            &ast::PatStruct(_, ref v, _) => {
                for p in v {
                    extract_idents(&p.node.pat.node, idents);
                }
            }
            &ast::PatVec(ref v1, ref opt, ref v2) => {
                for p in v1 {
                    extract_idents(&p.node, idents);
                }
                if let &Some(ref p) = opt {
                    extract_idents(&p.node, idents);
                }
                for p in v2 {
                    extract_idents(&p.node, idents);
                }
            }
            &ast::PatBox(ref p) | &ast::PatRegion(ref p, _) => extract_idents(&p.node, idents),
        }
    }
    let mut idents = vec!();
    for arg in decl.inputs.iter() {
        extract_idents(&arg.pat.node, &mut idents);
    }
    idents
}
```

The `arg_idents` function takes a function declaration and returns the names of all the arguments appearing in the declaration. It may look a bit complicted, but it's really not. It just recurses on each type of pattern you could have in a function argument until it finds an `Ident`, and then it adds it to a list.

In the `expand` function, we convert the `Vec<Ident>` to a `Vec<Token>` where each `Token` is just an `Ident`. Then we connect the `Ident` tokens with `Comma` tokens. Finally, we wrap each token in the `TtToken` variant of the `TokenTree` enum and return a vector of all the tokens. The tokens use a dummy span, which we'll talk about briefly later.

Now that we have a `TokenTree` we can create our format string and use this format string as well as our `TokenTree` in the `println!` function, and the code should compile.

One minor note unrelated to `TokenTree`s: what if we wanted to print something out after the original `$block` executed, instead of before? The naive approach would be to simply add a `println!` statement after the `$block`, but this will only work for functions that return `()`, and it also won't work for any functions that don't return at the end of the block, like when using `return` keyword. I've found the best way to handle this is to define a new `move` closure that contains the `$block` and then call that closure to get the return value. Then you can add whatever code you want to insert followed by returning the original return value.

## Spans and Error Reporting

A [Span](http://doc.rust-lang.org/syntax/codemap/struct.Span.html) maps a node to its location in the original source file. This is useful because we can report errors and refer directly to the source that's causing the problem. I've seen some syntax extensions that don't pay proper attention to which spans they're using, and as a result their error reporting isn't very helpful.

Like I mentioned earlier, many nodes like `Item_` have their span in their "wrapper" struct, which would be `Item` in this case. You can access the span using the field `span`. Other structs like [Decl](http://doc.rust-lang.org/syntax/ast/type.Decl.html) are just type aliases for a `Spanned` wrapper around their actual struct (in this case `Decl_`). The `Spanned` type just adds a `span` field to the struct, and you can get the original struct through the `node` field.

Our `expand` function also was passed a `Span` as an argument. This span covers the attribute itself, not the item it was applied to. If any errors occur in the expansion of the syntax extension that don't deal with a specific AST node, you should pass this span to the error reporting function. Otherwise, always pass the most specific span possible. Even when parsing `MetaItem`s (described below), you have a more specific span to use than just the attribute span, so you should use it. Also note that generated AST nodes should be given a span of `syntax::codemap::DUMMY_SP`, and these spans should never be used for error reporting.

To actually report errors, you can use the `span_*` functions in `ExtCtxt`, like `span_err`, `span_warn`, etc. Examples of this are shown in the "MetaItems" section.

## MetaItems

We haven't used the `MetaItem` argument of our `expand` function yet. A `MetaItem` is an option that our attribute can take. There are three variants of a [MetaItem_](http://doc.rust-lang.org/syntax/ast/enum.MetaItem_.html). The first is a `MetaWord`, which would like this: `#[extension(a_meta_word)]`. The second is a `MetaList`, which looks like this: `#[extension(first_item, second_item(is_also_a_meta_list)]`. Note that the elements of this list are also `MetaItem_`s, so you can have a list inside of a list. The last type of `MetaItem` is a `MetaNameValue`, which looks like this: `#[extension(name = "value")]`. Note that the type of the value is a `Lit`, but the only variant that works is `LitStr`. Also note that while I've been showing examples of using our extension attribute as a list, we can also use it as a `MetaNameValue`, i.e. `#[extension = "foo"]`. By itself (i.e. `#[extension]`), our attribute is a `MetaWord`, but since we can't change it to anything else this isn't really useful to us.

So if we wanted to parse a `MetaItem` that might like this: `#[extension(foo, bar = "str", list(list_item)]`, we could do it with the following code (only the new imports are included):

```
use syntax::ast::Lit_::LitStr;
use syntax::ast::MetaItem_::{MetaWord, MetaList, MetaNameValue};

fn parse_options(cx: &mut ExtCtxt, meta: &MetaItem) {
    if let MetaList(ref name, ref list) = meta.node {
        println!("Attribute name: {}", name);
        for item in list {
            match &item.node {
                &MetaNameValue(ref name, ref s) => {
                    if *name == "bar" {
                        if let LitStr(ref val, _) = s.node {
                            println!("bar: {}", val);
                        }
                    } else {
                        cx.span_warn(item.span, &format!("Invalid option {}", name));
                    }
                }
                &MetaList(ref name, _) => {
                    if *name == "list" {
                        // You can parse this list just like the top-level list if you want to
                        println!("Got another list");
                    } else {
                        cx.span_warn(item.span, &format!("Invalid option {}", name));
                    }
                }
                &MetaWord(ref name) => {
                    if *name == "foo" {
                        println!("Got MetaWord foo");
                    } else {
                        cx.span_warn(item.span, &format!("Invalid option {}", name))
                    }
                }
            }
        }
    }
}
```

## Conclusion

Hopefully by now you know enough to write your own syntax extensions. I hope that a lot of this information eventually makes its way into the [official documentation](https://doc.rust-lang.org/book/compiler-plugins.html), which is really lacking right now. If you want to learn more, one of the best things I can recommend is reading the source for any syntax extensions you come across. That and writing my own extension is how I figured all of this out. And if you want to do even cooler stuff, you should look into lints, which are a different type of compiler plugin that I've been meaning to start messing around with for a while. With lints you have access to type information as well, so you can do some really interesting things.

If you have any questions, feel free to leave a comment!
