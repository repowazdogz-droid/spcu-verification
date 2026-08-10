/* SPCU bare-metal driver interface.
 *
 * The linkage guard is load-bearing, not boilerplate. Verilator compiles the
 * .c driver with the C++ compiler, so without extern "C" the driver's symbols
 * are mangled while the harness that calls them expects C linkage. The link
 * then fails on a symbol whose signature looks perfectly correct, which is a
 * slow thing to debug from the error message alone.
 */

#ifndef SPCU_DRIVER_H
#define SPCU_DRIVER_H

#ifdef __cplusplus
extern "C" {
#endif

/* Number of failed checks from the last run of spcu_run_tests(). */
extern int spcu_failures;

/* Submit one DVFS request and poll to completion.
 * Returns 0 on success, 1 if the device reported ERROR, -1 on timeout. */
int spcu_request(int target);

int spcu_busy(void);
int spcu_current_pstate(void);

/* Run the full driver test suite. Returns the number of failures. */
int spcu_run_tests(void);

/* Implemented by the simulation harness only: sets the privilege the
 * simulated software agent presents on pprot[0]. Firmware cannot call this on
 * real hardware, which is precisely why the privilege dimension is exercised
 * from the harness rather than from the driver. */
void spcu_set_priv(int priv);

#ifdef __cplusplus
}
#endif

#endif /* SPCU_DRIVER_H */
