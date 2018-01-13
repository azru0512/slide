          ...

  llvm::FunctionType *funcType = 
      llvm::FunctionType::get(builder.getInt32Ty(), false);
  llvm::Function *mainFunc = 
      llvm::Function::Create(funcType,
                             llvm::Function::ExternalLinkage,
                             "main", module);

  module->dump( );
}
