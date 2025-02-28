#include <stdlib.h>
#include <unistd.h>

int main() {
    system("yad --title='E4S / Jupyter Lab' --window-icon=preferences-system-time \
        --center --text='<span font=\"16\"><b>🟢 Loading Jupyter Lab... Please wait.</b></span>' \
        --width=500 --height=200 --no-buttons --timeout=10 &");

    return system("singularity exec --nv /e4sonpremvm/E4S/24.02/e4s-cuda80-x86_64-24.11.sif bash -c \"cd ~ && jupyter-lab\"");
}
