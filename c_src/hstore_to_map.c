#include <string.h>
#include "erl_nif.h"

enum state {
  ZERO,
  KEY_START,
  KEY_STOP,
  MAP_START,
  MAP_STOP,
  VALUE_START,
  VALUE_STOP,
  ERROR
};

static ERL_NIF_TERM hstore_to_map(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2 || !enif_is_binary(env, argv[0]) || !enif_is_map(env, argv[1])) {
    return enif_make_badarg(env);
  }
  ErlNifBinary bin;
  if (!enif_inspect_binary(env, argv[0], &bin)) {
    return enif_make_badarg(env);
  }
  enum state state = ZERO;
  char * key = NULL, * value = NULL;
  int keysize = 0, valuesize = 0;
  for (int i = 0, len = bin.size; i < len; i ++) {
    switch (state) {
    case ZERO:
      if (bin.data[i] == '"') {
        state = KEY_START;
        key = (char *)bin.data + i + 1;
      }
      break;
    case KEY_START:
      if (bin.data[i] == '"') {
        state = KEY_STOP;
      } else {
        if (bin.data[i] == '\\') {
          if (i + 1 < len && bin.data[i] == '"') {
            keysize += 2;
            i ++;
          } else {
            keysize += 1;
          }
        } else {
          keysize += 1;
        }
      }
      break;
    case KEY_STOP:
      if (bin.data[i] == '=') {
        state = MAP_START;
      }
      break;
    case MAP_START:
      if (bin.data[i] == '>') {
        state = MAP_STOP;
      } else {
        state = ERROR;
      }
      break;
    case MAP_STOP:
      if (bin.data[i] == '"') {
        state = VALUE_START;
        value = (char *)bin.data + i + 1;
      }
      break;
    case VALUE_START:
      if (bin.data[i] == '"') {
        state = VALUE_STOP;
      } else {
        if (bin.data[i] == '\\') {
          if (i + 1 < len && bin.data[i] == '"') {
            valuesize += 2;
            i ++;
          } else {
            valuesize += 1;
          }
        } else {
          valuesize += 1;
        }
      }
      break;
    case ERROR:
      return enif_make_badarg(env);
      break;
    default:
      break;
    }
  }

  if (state != VALUE_STOP) {
    return enif_make_badarg(env);
  }

  if (keysize == 0) {
    return argv[1];
  }

  ErlNifBinary keybin, valuebin;

  if (!enif_alloc_binary(keysize, &keybin)) {
    goto error_alloc_key;
  }

  if (!enif_alloc_binary(valuesize, &valuebin)) {
    goto error_alloc_value;
  }

  memcpy(keybin.data, key, keysize);
  memcpy(valuebin.data, value, valuesize);

  ERL_NIF_TERM keyterm, valueterm, result;

  keyterm = enif_make_binary(env, &keybin);
  valueterm = enif_make_binary(env, &valuebin);

  if (!enif_make_map_put(env, argv[1], keyterm, valueterm, &result)) {
    goto error_map_put;
  }

  return result;
 error_map_put:
  enif_release_binary(&valuebin);
 error_alloc_value:
  enif_release_binary(&keybin);
 error_alloc_key:
  return argv[1];
}

static ErlNifFunc nifs [] = {
  {"hstore_to_map", 2, hstore_to_map, 0}
};

ERL_NIF_INIT(Elixir.PGPool, nifs, NULL, NULL, NULL, NULL)
