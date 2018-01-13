extern int foo(void);
extern int baz(void);

int bar(int x) {
  return x? foo() + 1 : baz();
}
