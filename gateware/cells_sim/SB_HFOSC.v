/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSEDPARAM */
(* blackbox *)
module SB_HFOSC(
	input TRIM0,
	input TRIM1,
	input TRIM2,
	input TRIM3,
	input TRIM4,
	input TRIM5,
	input TRIM6,
	input TRIM7,
	input TRIM8,
	input TRIM9,
	input CLKHFPU,
	input CLKHFEN,
	output CLKHF
);
parameter TRIM_EN = "0b0";
parameter CLKHF_DIV = "0b00";
endmodule
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
