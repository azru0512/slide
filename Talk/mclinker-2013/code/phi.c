
int foo() { return 1; }
int bar() { return 2; }

int baz(int x) {
  if (x)
    return foo();
  else
    return bar();
}
