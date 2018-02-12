<p align="center">
Copyright (c) 2018 陳韋任 (Chen Wei-Ren)<br><br>
</p>

RDF 全稱為 Register Dataflow Framework。是 Hexagon 後端針對暫存器分配之後所設計的一套數據流分析框架。更精確一點的說，此框架是運行在暫存器分配之後，已是非 SSA 形式的 MachineInstr 之上。其目的是希望重建近似 SSA 的數據流分析，以便類似於 [copy propagation](https://en.wikipedia.org/wiki/Copy_propagation) 和 [dead code elimination](https://en.wikipedia.org/wiki/Dead_code_elimination) 優化的展開。

RDF 基本分成三個部分:

- [RDFGraph](http://llvm.org/doxygen/RDFGraph_8h_source.html): 對程序建圖，圖中的節點分成兩類。一類是 `CodeNode`，代表程序的結構，由上至下分別為: `FuncNode`，`BlockNode` 和 `StmtNode`。分別對應到 `MachineFunction`，`MachineBasicBlock` 和 `MachineInstr`。另一類是 `RefNode` 用來表示指令中暫存器的 define 和 use，分別由 `DefNode` 和 `UseNode` 表示。


節點之間鏈結成一個 circular list。鏈結透過 Node Id 表示。

入口點為 [DataFlowGraph::build](http://llvm.org/doxygen/structllvm_1_1rdf_1_1DataFlowGraph.html#ac9b5de0f7d97d6989883bf591b1ba113)

- [RDFLiveness](http://llvm.org/doxygen/RDFLiveness_8h_source.html): 基於 RDFGraph 重建 [liveness](https://en.wikipedia.org/wiki/Live_variable_analysis) 訊息。

- [RDFCopy](http://llvm.org/doxygen/RDFCopy_8cpp_source.html) 和 [RDFDeadCode](http://llvm.org/doxygen/RDFDeadCode_8cpp_source.html): 根據 RDFLiveness 所計算的 liveness 所做的 copy propagation 和 dead code elimination。

- reaching def: 此暫存器的 producer 是誰。
- reached def: 此暫存器又被誰定義。
- reached use: 此暫存器的 consumer 是誰。
