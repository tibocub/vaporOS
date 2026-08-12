/*
 * A small, ordinary word-count utility. Nothing here was written with
 * NuttX in mind -- no nuttx/config.h, no FAR, no vapor-anything. Just
 * fopen/fgetc/getopt and standard C, the same code that would compile
 * on Linux or any other real Unix. Used as a portability smoke test:
 * if this drops in and works unmodified, that's the actual signal.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>

int main(int argc, char **argv)
{
    int show_lines = 0, show_words = 0, show_chars = 0;
    int opt;

    while ((opt = getopt(argc, argv, "lwc")) != -1)
    {
        switch (opt)
        {
            case 'l': show_lines = 1; break;
            case 'w': show_words = 1; break;
            case 'c': show_chars = 1; break;
            default:
                fprintf(stderr, "usage: %s [-lwc] [file]\n", argv[0]);
                return 1;
        }
    }

    if (!show_lines && !show_words && !show_chars)
    {
        show_lines = show_words = show_chars = 1;
    }

    FILE *in = stdin;
    const char *name = "-";

    if (optind < argc)
    {
        name = argv[optind];
        in = fopen(name, "r");

        if (in == NULL)
        {
            fprintf(stderr, "%s: cannot open %s\n", argv[0], name);
            return 1;
        }
    }

    long lines = 0, words = 0, chars = 0;
    int in_word = 0;
    int c;

    while ((c = fgetc(in)) != EOF)
    {
        chars++;

        if (c == '\n')
        {
            lines++;
        }

        if (isspace(c))
        {
            in_word = 0;
        }
        else if (!in_word)
        {
            in_word = 1;
            words++;
        }
    }

    if (in != stdin)
    {
        fclose(in);
    }

    if (show_lines) printf("%7ld ", lines);
    if (show_words) printf("%7ld ", words);
    if (show_chars) printf("%7ld ", chars);
    printf("%s\n", name);

    return 0;
}
