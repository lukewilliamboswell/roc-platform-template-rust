#include <stdio.h>
#include <stdlib.h>
#include <unwind.h>
static _Unwind_Reason_Code visit(struct _Unwind_Context *context, void *arg) {
    (void)context;
    (*(int *)arg)++;
    return _URC_NO_REASON;
}
int main(void) {
    int frames = 0;
    volatile char *memory = malloc(64);
    if (!memory) return 1;
    memory[0] = 42;
    int value = memory[0];
    free((void *)memory);
    _Unwind_Backtrace(visit, &frames);
    puts("runtime OK");
    return frames > 0 && value == 42 ? 0 : 2;
}
