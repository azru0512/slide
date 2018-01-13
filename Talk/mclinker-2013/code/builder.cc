// Create LLVMContext for latter use.
LLVMContext Context;

// Create some module to put our function into it.
Module *M = new Module("test", Context);

// Create function inside the module
Function *Add1F =
  cast<Function>(M->getOrInsertFunction("add1", Type::getInt32Ty(Context),
                                        Type::getInt32Ty(Context),
                                        (Type *)0));

// Add a basic block to the function.
BasicBlock *BB = BasicBlock::Create(Context, "EntryBlock", Add1F);

// Create a basic block builder. The builder will append instructions
// to the basic block 'BB'.
IRBuilder<> builder(BB);

// ... prepare operands for Add instrcution. ...

// Create the add instruction, inserting it into the end of BB.
Value *Add = builder.CreateAdd(One, ArgX);
