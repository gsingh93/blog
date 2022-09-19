---
layout: post
title: "How to write a display manager"
date: 2015-01-21 14:06:49 -0400
comments: true
published: true
tags: [display manager, linux, C]
---

Whenever I come across some topic of piece or software I don't completely understand, I always want to try writing it. When I was in high school, operating systems and compilers were two concepts that I tried to understand but couldn't completely get a grasp of just from reading books or articles online. That's why I ended up writing [both](http://gulshansingh.com/projects/gulbuntu/) of [them](http://gulshansingh.com/projects/compiler/). I've been curious about how [display/login managers](https://en.wikipedia.org/wiki/X_display_manager_\(program_type\)) and window managers work in Linux now for a while now. There are some tutorials on how to write a window manager online, but when it comes to display managers there's absolutely nothing. That's why I tried to write my own display manager and wrote this tutorial so you can write your own as well.

I'll be writing this in C, but the concepts apply to any language as long as the language you're using has all the necessary libraries. You can find my final code on [Github](https://github.com/gsingh93/display-manager/tree/tutorial) (this is the tutorial branch, which follows this tutorial more closely), and you might also find the [SLiM display manager](https://github.com/gsingh93/slim-display-manager) a useful reference as well. The SLiM website (which hosted the code) went down recently as the project is no longer maintained, so I've linked my mirror of the project above.

<!-- more -->

What is a Display Manager?
-------------------------
A display manager (also known as a login manager) is a graphical program that allows users to log into a computer. When your computer boots, the program that handles running startup programs (usually systemd or upstart) starts whatever display manager you've configured. This display manager then starts an X server and displays a GUI interface for you to log in to. After typing in your login credentials, the display manager uses [PAM](https://en.wikipedia.org/wiki/Pluggable_authentication_module) modules to log the user in. If the credentials are correct, the display manager starts whatever window manager you've configured and sets up some configuration variables. Common examples of display managers are GDM, KDM, and LightDM.

Overall, the process doesn't seem to hard, but there are some tricky issues I ran into over the course of this project:

### You can't start a display manager on a different virtual terminal with X server 1.16

This issue wasted a few days of my time. I'm using Arch Linux, which uses the latest version of `xorg-server`, version 1.16. Unfortunately, this release [made a change](https://www.archlinux.org/news/xorg-server-116-is-now-available/) I was not aware of:

> X is now rootless with the help of systemd-logind, this also means that it must be launched from the same virtual terminal as was used to log in, redirecting stderr also breaks rootless login.

When you start an X server, you can specify a VT (virtual terminal). Switch to a new VT (i.e. `Ctrl+Alt+F2`), and try running `/usr/bin/X :1` (we're using `:1` here because `:0` is probably taken. If that doesn't work, try higher numbers. If you don't understand this, don't worry, it'll be explained later). Your display should turn black. If you switch back to your original VT and run `pgrep X`. You should see the X server running. The thing is, when a display manager starts X, it uses the user specified VT, which could be something like VT 7. So it would run `/usr/bin/X :1 vt07`. Now if the display manager itself wasn't running on VT 7, on X server 1.16, X would segfault and disallow you from switching VTs, effectively forcing you to reboot your computer (note, I encountered various segfaults from X server in other scenarios as well, don't be surprised if you do too). If you're using something like Ubuntu, you probably won't need to worry about this for a while. If you want to get around this, using something like `chvt` might help, but I haven't tried it.

### Results vary based on your startup system and what window manager you launch after login

This was the main issue I had with this project. Different Linux distros and programs are used to start the display manager in real life (i.e. Ubuntu or Arch, systemd or upstart). Display managers like GDM are huge pieces of software with contributors who are often using these different configurations, so they can figure out how to handle them. Our display manager will work on Arch Linux with `dwm`, but has no guarantees for other configurations. It probably won't work without a bit of tweaking for other window manager like `Awesome WM` or `GNOME 3` (our display manager is very naive in the sense that it considers a logout to be when the window manager process terminates, which isn't always what window managers do).

Selecting your UI Toolkit
-------------------------
Most UI toolkits should work fine for designing the user interface of the display manager. This is one thing that surprised me at first: designing the GUI for a display manager is the same as designing the interface for a desktop application. It seems kind of obvious in retrospect, but I thought there would some hoops I'd have to jump through to get things to work, and fortunately there were none. I was originally going to create the GUI using [XCB](http://www.x.org/releases/X11R7.7/doc/libxcb/tutorial/index.html) or [Xlib](http://www.x.org/releases/X11R7.7/doc/libX11/libX11/libX11.html), but these languages don't have widgets like input boxes, so I'd have to write my own. I'm actually working on [my own UI toolkit](https://github.com/gsingh93/ui-toolkit) using XCB, but so far I've only implemented buttons and not text inputs, so using that isn't an option.

I've had some good experiences with Qt in the past, but there are some rendering issues with running Qt5 applications directly in Xephyr (which is a program we'll be using for testing), which is what we're using to test our display manager, so that option is out. I ended up deciding on using GTK3, since we're not doing too much GUI work anyway and I can use [Glade](https://glade.gnome.org/) to create the layout.

Creating the UI
---------------
Creating the user interface is the easy part of writing the display manager, especially since we're using Glade. With Glade, we can design the interface using a GUI interface designer, which gives us XML that GTK can render. The UI will consist of a text label and input field for both the username and password. Below the input fields, there is a text label that will contain status messages to inform the user of errors. These components will be centered vertically and horizontally on the screen. Here is how I made it using the Glade Interface Designer:

1. In the "Toplevels" section, click "Window". Change the Window ID in the "General" tab to "window".
2. In the "Containers" section, click "Box", and create a box with 1 vertical section. Go to the "Common" tab of the properties window and change the vertical alignment to "Center".
3. Create another Box in the middle section of the box created in step 2, also with 3 vertical sections.
4. Create another Box in the top two sections of the box created in step 3, but this time go to the "General" tab of the Box properties and set the number of items to 2 and the orientation to horizontal. Go to the common tab of the same Box and set the horizontal alignment to "Center".
5. In the two boxes created in step 4, put a Label in the left section and a Text Entry in the second section. These buttons can be found in the "Control and Display" section.
6. Go the the "General" tab for each Label and in the appearance section change the first one to "Username" and the second one to "Password".
7. For the first Text Entry, go to the "General" tab and change the ID to `username_text_entry`. For the second Text Entry, change it to `password_text_entry`. In the same tab, uncheck the "Visibility" for the password Text Entry. This is what causes dots to be displayed instead of characters when a password is typed.
8. Finally, create a label in the last section of the Box created in step 3. Change the ID of this label to `status_label`, and remove the label text.

At this point what you have should look like this:

{% img center /images/gui_ui.png %}

Save the file as `gui.ui`. In case something went wrong in the above steps or you simply didn't want to make the UI yourself, feel free to use my version of [gui.ui](https://github.com/gsingh93/display-manager/blob/tutorial/gui.ui).

Note that while this UI is simple, you can do anything you can do in a normal desktop application. Feel free to add images, colors, animations, etc. I'm hoping someone will use this starting point to make a really well designed display manager.

Testing the UI
--------------
Now that we have our UI, let's actually write some code to display it. Put the following code into `display-manager.c`:

``` c display-manager.c
#include <libgen.h> // dirname()
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <gtk/gtk.h>

#define UI_FILE     "gui.ui"
#define WINDOW_ID   "window"
#define USERNAME_ID "username_text_entry"
#define PASSWORD_ID "password_text_entry"
#define STATUS_ID   "status_label"

static GtkEntry *user_text_field;
static GtkEntry *pass_text_field;
static GtkLabel *status_label;

int main(int argc, char *argv[]) {
    gtk_init(&argc, &argv);

    char ui_file_path[256];
    if (readlink("/proc/self/exe", ui_file_path, sizeof(ui_file_path)) == -1) {
        printf("Error: could not get location of binary");
        exit(1);
    }

    dirname(ui_file_path);
    strcat(ui_file_path, "/" UI_FILE);
    GtkBuilder *builder = gtk_builder_new_from_file(ui_file_path);
    GtkWidget *window = GTK_WIDGET(gtk_builder_get_object(builder, WINDOW_ID));
    user_text_field = GTK_ENTRY(gtk_builder_get_object(builder, USERNAME_ID));
    pass_text_field = GTK_ENTRY(gtk_builder_get_object(builder, PASSWORD_ID));
    status_label = GTK_LABEL(gtk_builder_get_object(builder, STATUS_ID));

    // Make full screen
    GdkScreen *screen = gdk_screen_get_default();
    gint height = gdk_screen_get_height(screen);
    gint width = gdk_screen_get_width(screen);
    gtk_widget_set_size_request(GTK_WIDGET(window), width, height);
    gtk_widget_show(window);

    g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    gtk_main();

    return 0;
}
```

Most things should be self explanatory (if they aren't search for some GTK tutorials), but there are a few things to note:

- The `readlink`/`ui_file_path` code is so you can run the display manager from different directories. If you didn't do this, then if you didn't run the program from the directory where `gui.ui` is located, it wouldn't be found. See [this](http://stackoverflow.com/questions/933850/how-to-find-the-location-of-the-executable-in-c) StackOverflow question for more details.
- Our display manager should be full screen so when the user sees it when the system boots, it takes up the whole screen. We can't use the `gtk_window_fullscreen` function, because that's a hint to the window manager to make the window full screen, but our display manager won't be running in a window manager. Instead, we simply get the screen dimensions and set the window dimensions to match them.

This `Makefile` should take care of building the code (as long as you have GTK3 installed properly):

``` makefile Makefile
all: display-manager

display-manager: display-manager.c
	gcc `pkg-config --cflags --libs gtk+-3.0` -Wall -o $@ $^

.PHONY: clean

clean:
	rm -f display-manager
```

You should now be able to run `make` followed by `./display-manager` and see the following screen:

{% img center /images/display-manager.png %}

Testing with Xephyr
-------------------

Being able to launch our display manager is nice, but eventually we want our display manager to run without a window manager, directly on top of an X server. Normally the way this is done is by manually starting an X server when the display manager starts, and we would test this by switching over to a virtual terminal (where X isn't running) and then run our display manager. This method is error prone and time consuming, so we only want to do it when we're doing our final testing. Until then, we can use a program called Xephyr (should be available in your package manager). Xephyr is essentially an X11 server inside a window, so if we set our `DISPLAY` environment variable to Xephyr's display number, we can launch applications in it.

Start Xephyr with `Xephyr -ac -br -noreset -screen 800x600 :1` (I've aliased this to just `xephyr`). Note the `:1` at the end. That's saying the display number of `xephyr` is one. We use one, because they display you're on right now is probably using zero, and we can't share display numbers. If you want to check what display number you're currently using, type `echo $DISPLAY` in a terminal. If you want to see all display numbers in use, look at the output of `ps aux | grep X`.

Launch our window manager in Xephyr with `DISPLAY=:1 ./display-manager`. The `DISPLAY=:1` sets the `DISPLAY` environment variable to one for just our display manager process, so when we run it, it starts in Xephyr, not in our normal window manager.

Handling User Input
-------------------

Now we need to get the user input and send it to the login function. Here is the updated `display-manager.c`, the explanation will follow:

``` c display-manager.c
#include <libgen.h> // dirname()
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <gtk/gtk.h>

#define ENTER_KEY    65293
#define ESC_KEY      65307
#define UI_FILE     "gui.ui"
#define WINDOW_ID   "window"
#define USERNAME_ID "username_text_entry"
#define PASSWORD_ID "password_text_entry"
#define STATUS_ID   "status_label"

static GtkEntry *user_text_field;
static GtkEntry *pass_text_field;
static GtkLabel *status_label;

static pthread_t login_thread;

bool login(const char *username, const char *password, pid_t *child_pid) {
    return false;
}

bool logout(void) {
    return false;
}

static void* login_func(void *data) {
    GtkWidget *widget = GTK_WIDGET(data);
    const gchar *username = gtk_entry_get_text(user_text_field);
    const gchar *password = gtk_entry_get_text(pass_text_field);

    gtk_label_set_text(status_label, "Logging in...");
    pid_t child_pid;
    if (login(username, password, &child_pid)) {
        gtk_widget_hide(widget);

        // Wait for child process to finish (wait for logout)
        int status;
        waitpid(child_pid, &status, 0);
        gtk_widget_show(widget);

        gtk_label_set_text(status_label, "");

        logout();
    } else {
        gtk_label_set_text(status_label, "Login error");
    }
    gtk_entry_set_text(pass_text_field, "");

    return NULL;
}

static gboolean key_event(GtkWidget *widget, GdkEventKey *event) {
    if (event->keyval == ENTER_KEY) {
        pthread_create(&login_thread, NULL, login_func, (void*) widget);
    } else if (event->keyval == ESC_KEY) {
        gtk_main_quit();
    }
    return FALSE;
}

int main(int argc, char *argv[]) {
    gtk_init(&argc, &argv);

    char ui_file_path[256];
    if (readlink("/proc/self/exe", ui_file_path, sizeof(ui_file_path)) == -1) {
        printf("Error: could not get location of binary");
        exit(1);
    }

    dirname(ui_file_path);
    strcat(ui_file_path, "/" UI_FILE);
    GtkBuilder *builder = gtk_builder_new_from_file(ui_file_path);
    GtkWidget *window = GTK_WIDGET(gtk_builder_get_object(builder, WINDOW_ID));
    user_text_field = GTK_ENTRY(gtk_builder_get_object(builder, USERNAME_ID));
    pass_text_field = GTK_ENTRY(gtk_builder_get_object(builder, PASSWORD_ID));
    status_label = GTK_LABEL(gtk_builder_get_object(builder, STATUS_ID));

    // Make full screen
    GdkScreen *screen = gdk_screen_get_default();
    gint height = gdk_screen_get_height(screen);
    gint width = gdk_screen_get_width(screen);
    gtk_widget_set_size_request(GTK_WIDGET(window), width, height);
    gtk_widget_show(window);

    g_signal_connect(window, "key-release-event", G_CALLBACK(key_event), NULL);
    g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    gtk_main();

    return 0;
}
```

Here are the changes to note:

- We've connected the `key-release-event` signal on the window to the `key_event` callback.
- The `key_event` callback checks if either enter or escape are pressed. If escape is pressed, we quit the application. This is useful for killing the display manager when you're running on a virtual terminal (you might want to disable this before releasing your display manager). If enter is pressed, we start the login process, by starting a thread which runs the `login_thread` function.
- In the `login_thread` function, we simply get the users input and send it to our stub `login` function. If the function returns true, that means the login was successful, so we need to hide our display manager, and wait for the processes we've started to finish (i.e. wait until the user logs out or quits the window manager). Once the process we launched finishes, the thread resumes and shows our display manager again. The `login_thread` function also updates the status label if there are any errors.

If you've used GTK before and have done any basic multithreading work in C before, these changes should be straightforward. However, you might be wondering why we're even starting a new thread in the first place? Well, this is another tricky "gotcha" I ran into when writing this display manager (you're lucky you don't have to deal with all this!). When I ran the `login` function in the `key_event` function, I found that the display manager window didn't properly hide, so I wasn't able to use the window manager that was launched. What I eventually realized is that if I call `waitpid` inside `key_event` function, then I never return to the main GTK event looped that was launched with `gtk_main()`, so GTK never is able to update the screen. Another way of saying this, is we're blocking the UI thread. Thus, we need to do any blocking operations on a new thread.

Another thing to note is we're using a single, global, `pthread_t` object in our application. The reason we don't put this variable in the key event function is again, we can't block that function, but if we don't block it then our stack allocated structure will be cleaned up too early. But if we allocate on the heap, cleaning up that memory will be tricky (since we're relying on `GTK` callbacks to execute our code). Since we're only forking one process at a time, having a single, global `pthread_t` works fine.

User Authentication
-------------------
Now that we have a user interface, we have to write the user authentication code. First make two new files, `pam.h` and `pam.c`. In `pam.h`, write the following:

``` c pam.h
#ifndef _PAM_H_
#define _PAM_H_

#include <stdbool.h>

bool login(const char *username, const char *password, pid_t *child_pid);
bool logout(void);

#endif /* _PAM_H_ */
```

As you can see, we're just declaring the prototypes of the stub functions we declared in `display-manager.c`. You can now remove those stub functions and import `pam.h`. Let's start with the declarations we need in `pam.c`:

``` c pam.c
#include <security/pam_appl.h>
#include <security/pam_misc.h>

#include <pwd.h>
#include <paths.h>

#include "pam.h"

#define SERVICE_NAME "display_manager"

#define err(name)                                   \
    do {                                            \
        fprintf(stderr, "%s: %s\n", name,           \
                pam_strerror(pam_handle, result));  \
        end(result);                                \
        return false;                               \
    } while (1);                                    \

static void init_env(struct passwd *pw);
static void set_env(char *name, char *value);
static int end(int last_result);

static int conv(int num_msg, const struct pam_message **msg,
                struct pam_response **resp, void *appdata_ptr);

static pam_handle_t *pam_handle;
```

We'll walk through implementing the `login`/`logout` functions as well as all of the functions whose prototypes you see here one by one. For now, the only somewhat important thing is the `err` macro, which is a convenient way to handle errors from PAM. If the `do while` notation here confuses you, it's just a trick for defining multiline macros.

Here's the `login` function:

``` c pam.c
bool login(const char *username, const char *password, pid_t *child_pid) {
    const char *data[2] = {username, password};
    struct pam_conv pam_conv = {
        conv, data
    };

    int result = pam_start(SERVICE_NAME, username, &pam_conv, &pam_handle);
    if (result != PAM_SUCCESS) {
        err("pam_start");
    }

    result = pam_authenticate(pam_handle, 0);
    if (result != PAM_SUCCESS) {
        err("pam_authenticate");
    }

    result = pam_acct_mgmt(pam_handle, 0);
    if (result != PAM_SUCCESS) {
        err("pam_acct_mgmt");
    }

    result = pam_setcred(pam_handle, PAM_ESTABLISH_CRED);
    if (result != PAM_SUCCESS) {
        err("pam_setcred");
    }

    result = pam_open_session(pam_handle, 0);
    if (result != PAM_SUCCESS) {
        pam_setcred(pam_handle, PAM_DELETE_CRED);
        err("pam_open_session");
    }

    struct passwd *pw = getpwnam(username);
    init_env(pw);

    *child_pid = fork();
    if (*child_pid == 0) {
        chdir(pw->pw_dir);
        // We don't use ~/.xinitrc because we should already be in the users home directory
        char *cmd = "exec /bin/bash --login .xinitrc";
        execl(pw->pw_shell, pw->pw_shell, "-c", cmd, NULL);
        printf("Failed to start window manager");
        exit(1);
    }

    return true;
}
```

In order to understand the `login` function, we'll need to first understand a bit about how [PAM](http://www.linux-pam.org/Linux-PAM-html/Linux-PAM_ADG.html) works. PAM authentication starts with a call to `pam_start()`. We pass this function the name of our service, the username, a PAM conversion struct, and a PAM handle. The handle is the structure that we pass to each PAM function; it's essentially the state of our PAM session. The PAM conversion struct has two members, a pointer to a conversion function (which we'll talk about later) and some data that we want to use in the conversion function. In this case, we'll need the username and password.

Next you call `pam_authenticate` to see if the username and password are valid. At this point, `pam_authenticate` gets any information it didn't have using the [conversation function](http://www.linux-pam.org/Linux-PAM-html/adg-interface-of-app-expected.html#adg-pam_conv). PAM will call the conversation function you provided in the struct passed to `pam_start` for every bit of data that it needs, passing the second field of the struct as an argument to the function. Here's my implementation of the conversation function:

``` c pam.c
static int conv(int num_msg, const struct pam_message **msg,
                struct pam_response **resp, void *appdata_ptr) {
    int i;

    *resp = calloc(num_msg, sizeof(struct pam_response));
    if (*resp == NULL) {
        return PAM_BUF_ERR;
    }

    int result = PAM_SUCCESS;
    for (i = 0; i < num_msg; i++) {
        char *username, *password;
        switch (msg[i]->msg_style) {
        case PAM_PROMPT_ECHO_ON:
            username = ((char **) appdata_ptr)[0];
            (*resp)[i].resp = strdup(username);
            break;
        case PAM_PROMPT_ECHO_OFF:
            password = ((char **) appdata_ptr)[1];
            (*resp)[i].resp = strdup(password);
            break;
        case PAM_ERROR_MSG:
            fprintf(stderr, "%s\n", msg[i]->msg);
            result = PAM_CONV_ERR;
            break;
        case PAM_TEXT_INFO:
            printf("%s\n", msg[i]->msg);
            break;
        }
        if (result != PAM_SUCCESS) {
            break;
        }
    }

    if (result != PAM_SUCCESS) {
        free(*resp);
        *resp = 0;
    }

    return result;
}
```
If the `msg_style` is `PAM_PROMPT_ECHO_ON`, it's asking for the username, and if the `msg_style` is `PAM_PROMPT_ECHO_OFF`, it's asking for the password. The other two options are described in the spec and are used for error and informational messages. Depending on the message type, we populate the `resp` array with the corresponding responses. Note that our implementation for the `PAM_PROMPT_ECHO_ON` here is redundant, because we've already provided the username in `pam_start`, but I'm leaving it here just in case anyone ever needs that functionality.

If `pam_authenticate` returns `PAM_SUCCESS`, that means the user exists. We then have to call `pam_acct_mgmt` to make sure the user has permission to login at this time (I'll be honest, I don't know where or how this permission is set, but it's safe to do it anyway).

Now we can get an authentication token using `pam_setcred` and then open a session with `pam_open_session`. At this point, the user is pretty much logged in. We get information about their home directory and preferred shell from the `getpwnam` function, and we use this data to initialize the environment variables. Here's the code that initializes those environment variables:

``` c pam.c
static void init_env(struct passwd *pw) {
    set_env("HOME", pw->pw_dir);
    set_env("PWD", pw->pw_dir);
    set_env("SHELL", pw->pw_shell);
    set_env("USER", pw->pw_name);
    set_env("LOGNAME", pw->pw_name);
    set_env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/bin");
    set_env("MAIL", _PATH_MAILDIR);

    size_t xauthority_len = strlen(pw->pw_dir) + strlen("/.Xauthority") + 1;
    char *xauthority = malloc(xauthority_len);
    snprintf(xauthority, xauthority_len, "%s/.Xauthority", pw->pw_dir);
    set_env("XAUTHORITY", xauthority);
    free(xauthority);
}

static void set_env(char *name, char *value) {
    // The `+ 2` is for the '=' and the null byte
    size_t name_value_len = strlen(name) + strlen(value) + 2;
    char *name_value = malloc(name_value_len);
    snprintf(name_value, name_value_len,  "%s=%s", name, value);
    pam_putenv(pam_handle, name_value);
    free(name_value);
}
```

Finally, we `fork` and start a shell that executes the users `.xinitrc`, which should start the window manager.

The `logout` function is much more simple:
``` c pam.c
bool logout(void) {
    int result = pam_close_session(pam_handle, 0);
    if (result != PAM_SUCCESS) {
        pam_setcred(pam_handle, PAM_DELETE_CRED);
        err("pam_close_session");
    }

    result = pam_setcred(pam_handle, PAM_DELETE_CRED);
    if (result != PAM_SUCCESS) {
        err("pam_setcred");
    }

    end(result);
    return true;
}

static int end(int last_result) {
    int result = pam_end(pam_handle, last_result);
    pam_handle = 0;
    return result;
}

```
Remember that this is called from the `login_func` function back `display-manager.c`. When the process we started in `login` exits, we need to end the PAM session. We simply close the session with `pam_close_session`, delete the credentials with `pam_setcred`, and then finish with `pam_end` in that order.

If you didn't follow all that, that's fine. The PAM documentation is long and dense, and honestly I don't understand every detail of it either. The important thing is that you now have working code to log the user in, and you can worry about more important things.

Note that you'll have to update the makefile `display-manager` target to look like this:
``` makefile Makefile
display-manager: display-manager.c pam.c
	gcc `pkg-config --cflags --libs gtk+-3.0` -l pam -Wall -o $@ $^
```

This requires you to have the PAM package and development headers installed on your system, which varies based on your distro.

If you build and launch the display manager on Xephyr now, you'll see that you can login to a window manager (try putting something like `exec dwm` in `~/.xinitrc`, assuming you have `dwm` installed). If you exit out of your window manager, you should be dropped back into the display manager. `dwm` is a very simple window manager, which is why I like to test with it. Our simple display manager probably won't work with more complicated window managers. Note that you can quit out of `dwm` with `Shift + Alt + q`.

Starting an X server
--------------------

Our display manager is eventually going to have to run without Xephyr, so it's going to need to start an X server on it's own. Add the following code to `display-manager.c`:

``` c display-manager.c
static pid_t x_server_pid;

static void start_x_server(const char *display, const char *vt) {
    x_server_pid = fork();
    if (x_server_pid == 0) {
        char cmd[32];
        snprintf(cmd, sizeof(cmd), "/usr/bin/X %s %s", display, vt);
        execl("/bin/bash", "/bin/bash", "-c", cmd, NULL);
        printf("Failed to start X server");
        exit(1);
    } else {
        sleep(1);
    }
}

static void stop_x_server() {
    if (x_server_pid != 0) {
        kill(x_server_pid, SIGKILL);
    }
}

static void sig_handler(int signo) {
    stop_x_server();
}
```

The `start_x_server` function simply calls the `/usr/bin/X` program with the given display number and virtual terminal number. We fork and store X server PID in our static global variable (so we can access it in `stop_x_server`), and in the parent process we wait for a second to let the server startup. In production code, you'd actually try continuously connecting to the display here programmatically using the X11 API, but this isn't production code (SLiM does this, take a look at that code if you're interested).

Now set the default values for the display and virtual terminal using defines:

``` c display-manager.c
#define DISPLAY     ":1"
#define VT          "vt01"
```

And update main to look like this:

``` c display-manager.c
static bool testing = false;

int main(int argc, char *argv[]) {
    const char *display = DISPLAY;
    const char *vt = VT;
    if (argc == 3) {
        display = argv[1];
        vt = argv[2];
    }
    if (!testing) {
        signal(SIGSEGV, sig_handler);
        signal(SIGTRAP, sig_handler);
        start_x_server(display, vt);
    }
    setenv("DISPLAY", display, true);

    gtk_init(&argc, &argv);

    ...

    stop_x_server();

    return 0;
}
```

Essentially we're saying is that if the `testing` flag is set, don't start an X server because we want to use something like Xephyr. We also make sure to shutdown the X server when our display manager exits.

Testing the display manager
---------------------------
The last thing to do is to test that the display manager actually works when the system boots up. Again this is highly system dependent, so your results may vary. I'll be describing the process for Arch Linux. Also note that we're messing with the program that starts when you boot your system up, so make sure you know how to fix things if something goes wrong (you can use other virtual terminals or boot in single user mode).

Create a new systemd service file called `my-display-manager.service`:

``` ini my-display-manager.service
[Unit]
Description=My Display Manager
After=systemd-user-sessions.service

[Service]
ExecStart=/path/to/my/display-manager

[Install]
Alias=display-manager.service
```

Put the script in `/usr/lib/systemd/system/` and enable it with `systemctl enable my-display-manager.service`. Reboot, and hopefully you'll see your display manager. Try logging in and then quitting the window manager to make sure everything works fine.

Conclusion
----------
Hopefully by now you understand how display managers work and have your own working display manager. It took me a while to figure out all of this information, so I hope this article makes life a bit easier for anyone else who want to write their own display manager. Some important things to note, however, include the fact that some systems (like Arch) use `systemd-login` now, which might complicate things if you want to release a production quality display manager. Another issue is that your display manager should be able to boot fine on various Linux distros and run any window manager after login, and I don't believe ours does that (when I tested with Awesome, I could log in fine, but on quitting I couldn't type in the username/password fields anymore). In any case, this is a good first step. If you have any questions or would like to share a display manager you've made, feel free to post in the comments section.
