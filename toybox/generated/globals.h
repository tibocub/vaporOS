struct mkdir_data {
  char *m, *Z;
};

struct touch_data {
  char *t, *r, *d;
};
extern union global_union {
	struct mkdir_data mkdir;
	struct touch_data touch;
} this;
