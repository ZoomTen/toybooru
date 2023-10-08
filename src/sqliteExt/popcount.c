// https://gist.github.com/kylelk/39fed416b0125dbbe62e

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sqlite3ext.h>

SQLITE_EXTENSION_INIT1

int calculate_popcount(uint64_t value){
  value -= (value >> 1) & 0x5555555555555555;
  value = (value & 0x3333333333333333) + ((value >> 2) & 0x3333333333333333);
  value = (value + (value >> 4)) & 0x0f0f0f0f0f0f0f0f;
  return (value * 0x0101010101010101) >> 56;
}

static void popcount(sqlite3_context *context, int argc, sqlite3_value **argv){
    if( argc<1 ) return;
    uint64_t rVal = NULL;
    int result = NULL;
    int datatype_arg1 = NULL, datatype_arg2 = NULL;
    if (argc >= 1){
        datatype_arg1 = sqlite3_value_type(argv[0]);
    }
    if (argc >= 2) {
        datatype_arg2 = sqlite3_value_type(argv[1]);
    }

    if (argc == 1 && (datatype_arg1 == SQLITE_INTEGER || datatype_arg1 == SQLITE_FLOAT)) {
        rVal = sqlite3_value_int64(argv[0]);
        rVal = calculate_popcount(rVal);
        sqlite3_result_int(context, rVal);
    }
    else if (
            argc >= 2 && 
            (datatype_arg1 == SQLITE_INTEGER || datatype_arg1 == SQLITE_FLOAT) &&
            (datatype_arg2 == SQLITE_INTEGER || datatype_arg2 == SQLITE_FLOAT)) {
        rVal = sqlite3_value_int64(argv[0]);
        uint64_t num1 = sqlite3_value_int64(argv[0]);
        uint64_t num2 = sqlite3_value_int64(argv[1]);
        rVal = calculate_popcount(num1 ^ num2);
        sqlite3_result_int(context, rVal);
    }
    else { 
        sqlite3_result_null(context);
        return;
    }
}

int init_sqlite(sqlite3 *db){
    sqlite3_create_function(db, "popcount", -1, SQLITE_ANY, 0, popcount, 0, 0);
}

#ifdef _WIN32
__declspec(dllexport)
#endif

int sqlite3_extension_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi){
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);
  return init_sqlite(db);
}
