#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static void hook(const char *helper, const char *event, const char *payload) {
    int input[2];
    if (pipe(input) != 0) exit(2);
    pid_t child = fork();
    if (child == 0) {
        close(input[1]);
        dup2(input[0], STDIN_FILENO);
        close(input[0]);
        execl(helper, helper, "hook", "codex", event, NULL);
        _exit(3);
    }
    if (child < 0) exit(4);
    close(input[0]);
    FILE *stream = fdopen(input[1], "w");
    if (!stream) exit(5);
    fputs(payload, stream);
    fclose(stream);
    int status = 0;
    waitpid(child, &status, 0);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) exit(6);
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    hook(argv[1], "UserPromptSubmit", "{\"session_id\":\"nuphybar-owner-smoke\",\"turn_id\":\"owner-smoke-turn\"}");
    hook(argv[1], "UserPromptSubmit", "{\"session_id\":\"nuphybar-interrupt-smoke\",\"turn_id\":\"interrupt-smoke-turn\"}");
    hook(argv[1], "Interrupt", "{\"session_id\":\"nuphybar-interrupt-smoke\",\"turn_id\":\"interrupt-smoke-turn\"}");
    puts("Owner is alive; interrupted task ended. Owner exits after 15 seconds.");
    fflush(stdout);
    sleep(15);
    return 0;
}
