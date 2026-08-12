/*
 * An even more minimal portability test than portable_wc: pure ISO C
 * stdio, nothing else. No getopt, no unistd.h -- not even the mild
 * POSIX dependency portable_wc has. If a language's own standard
 * library compiles and runs unmodified, that's about as strong a
 * portability signal as this tier can give.
 */

#include <stdio.h>

int main(int argc, char **argv)
{
    int i;

    if (argc < 2)
    {
        FILE *in = stdin;
        int c;

        while ((c = fgetc(in)) != EOF)
        {
            fputc(c, stdout);
        }

        return 0;
    }

    for (i = 1; i < argc; i++)
    {
        FILE *in = fopen(argv[i], "r");

        if (in == NULL)
        {
            fprintf(stderr, "%s: cannot open %s\n", argv[0], argv[i]);
            continue;
        }

        int c;

        while ((c = fgetc(in)) != EOF)
        {
            fputc(c, stdout);
        }

        fclose(in);
    }

    return 0;
}
