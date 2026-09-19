#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(void) {
    char line[64];
    printf("MOCK_READY pid=%ld pgid=%ld foreground=%ld wrapper=%ld\n",
           (long)getpid(), (long)getpgrp(), (long)tcgetpgrp(STDIN_FILENO), (long)getppid());
    fflush(stdout);
    if (!fgets(line, sizeof(line), stdin)) return 9;
    const char *status = getenv("MOCK_EXIT");
    return status ? atoi(status) : 0;
}
