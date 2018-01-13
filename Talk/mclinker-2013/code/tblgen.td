let Predicates = [isInteger] in
  def ADDrc : RcInstr<0x8b, // op1
                      0x00, // op2
                      (outs DR:$c), // outs
                      (ins DR:$a, s9imm:$const9), // ins
                      "addnt$c, $a, $const9", // asmString
                      [(set DR:$c, (add DR:$a, immSExt9:$const9))]>;
