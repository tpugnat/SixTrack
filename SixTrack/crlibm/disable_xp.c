/* Initialise the IA32/64 FPU flags from Fortran */
/* An init function which sets FPU flags when needed */
#include <fpu_control.h>
void disable_xp_() {
  /* Set FPU flags to use double, not double extended,
     with rounding to nearest */
  short unsigned int cw = (_FPU_DEFAULT & ~_FPU_EXTENDED)|_FPU_DOUBLE;
  _FPU_SETCW(cw);
}