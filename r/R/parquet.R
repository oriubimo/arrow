# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

#' Read a Parquet file
#'
#' '[Parquet](https://parquet.apache.org/)' is a columnar storage file format.
#' This function enables you to read Parquet files into R.
#'
#' @inheritParams read_delim_arrow
#' @param props [ParquetReaderProperties]
#' @param ... Additional arguments passed to `ParquetFileReader$create()`
#'
#' @return A [arrow::Table][Table], or a `data.frame` if `as_data_frame` is
#' `TRUE` (the default).
#' @examples
#' \donttest{
#' df <- read_parquet(system.file("v0.7.1.parquet", package="arrow"))
#' head(df)
#' }
#' @export
read_parquet <- function(file,
  col_select = NULL,
  as_data_frame = TRUE,
  props = ParquetReaderProperties$create(),
  ...) {
  reader <- ParquetFileReader$create(file, props = props, ...)
  tab <- reader$ReadTable(!!enquo(col_select))

  if (as_data_frame) {
    tab <- as.data.frame(tab)
  }
  tab
}

#' Write Parquet file to disk
#'
#' [Parquet](https://parquet.apache.org/) is a columnar storage file format.
#' This function enables you to write Parquet files from R.
#'
#' @param x An [arrow::Table][Table], or an object convertible to it.
#' @param sink an [arrow::io::OutputStream][OutputStream] or a string which is interpreted as a file path
#' @param chunk_size chunk size in number of rows. If NULL, the total number of rows is used.
#'
#' @param version parquet version, "1.0" or "2.0". Default "1.0"
#' @param compression compression algorithm. Default "snappy". See details.
#' @param compression_level compression level. Meaning depends on compression algorithm
#' @param use_dictionary Specify if we should use dictionary encoding. Default `TRUE`
#' @param write_statistics Specify if we should write statistics. Default `TRUE`
#' @param data_page_size Set a target threshold for the approximate encoded
#'    size of data pages within a column chunk (in bytes). Default 1 MiB.
#' @param properties properties for parquet writer, derived from arguments
#'   `version`, `compression`, `compression_level`, `use_dictionary`,
#'   `write_statistics` and `data_page_size`. You should not specify any of
#'    these arguments if you also provide a `properties` argument, as they will
#'    be ignored.
#'
#' @param use_deprecated_int96_timestamps Write timestamps to INT96 Parquet format. Default `FALSE`.
#' @param coerce_timestamps Cast timestamps a particular resolution. Can be
#'   `NULL`, "ms" or "us". Default `NULL` (no casting)
#' @param allow_truncated_timestamps Allow loss of data when coercing timestamps to a
#'    particular resolution. E.g. if microsecond or nanosecond data is lost when coercing
#'    to "ms", do not raise an exception
#'
#' @param arrow_properties arrow specific writer properties, derived from arguments
#'   `use_deprecated_int96_timestamps`, `coerce_timestamps` and `allow_truncated_timestamps`
#'    You should not specify any of these arguments if you also provide a `properties`
#'    argument, as they will be ignored.
#'
#' @details The parameters `compression`, `compression_level`, `use_dictionary` and
#'   `write_statistics` support various patterns:
#'
#'  - The default `NULL` leaves the parameter unspecified, and the C++ library
#'    uses an appropriate default for each column (defaults listed above)
#'  - A single, unnamed, value (e.g. a single string for `compression`) applies to all columns
#'  - An unnamed vector, of the same size as the number of columns, to specify a
#'    value for each column, in positional order
#'  - A named vector, to specify the value for the named columns, the default
#'    value for the setting is used when not supplied
#'
#' The `compression` argument can be any of the following (case insensitive):
#' "uncompressed", "snappy", "gzip", "brotli", "zstd", "lz4", "lzo" or "bz2".
#' Only "uncompressed" is guaranteed to be available, but "snappy" and "gzip"
#' are almost always included. See [codec_is_available()].
#' The default "snappy" is used if available, otherwise "uncompressed". To
#' disable compression, set `compression = "uncompressed"`.
#' Note that "uncompressed" columns may still have dictionary encoding.
#'
#' @return the input `x` invisibly.
#'
#' @examples
#' \donttest{
#' tf1 <- tempfile(fileext = ".parquet")
#' write_parquet(data.frame(x = 1:5), tf1)
#'
#' # using compression
#' tf2 <- tempfile(fileext = ".gz.parquet")
#' write_parquet(data.frame(x = 1:5), tf2, compression = "gzip", compression_level = 5)
#'
#' }
#' @export
write_parquet <- function(x,
  sink,
  chunk_size = NULL,

  # writer properties
  version = NULL,
  compression = NULL,
  compression_level = NULL,
  use_dictionary = NULL,
  write_statistics = NULL,
  data_page_size = NULL,

  properties = ParquetWriterProperties$create(
    x,
    version = version,
    compression = compression,
    compression_level = compression_level,
    use_dictionary = use_dictionary,
    write_statistics = write_statistics,
    data_page_size = data_page_size
  ),

  # arrow writer properties
  use_deprecated_int96_timestamps = FALSE,
  coerce_timestamps = NULL,
  allow_truncated_timestamps = FALSE,

  arrow_properties = ParquetArrowWriterProperties$create(
    use_deprecated_int96_timestamps = use_deprecated_int96_timestamps,
    coerce_timestamps = coerce_timestamps,
    allow_truncated_timestamps = allow_truncated_timestamps
  )
) {
  x_out <- x
  x <- to_arrow(x)

  if (is.character(sink)) {
    sink <- FileOutputStream$create(sink)
    on.exit(sink$close())
  } else if (!inherits(sink, "OutputStream")) {
    abort("sink must be a file path or an OutputStream")
  }

  schema <- x$schema
  # Match the pyarrow default (overriding the C++ default)
  if (is.null(compression) && codec_is_available("snappy")) {
    compression <- "snappy"
  }
  # Note: `properties` and `arrow_properties` are not actually $create()-ed
  # until the next line, so the compression change is applied.
  writer <- ParquetFileWriter$create(schema, sink, properties = properties, arrow_properties = arrow_properties)
  writer$WriteTable(x, chunk_size = chunk_size %||% x$num_rows)
  writer$Close()

  invisible(x_out)
}


ParquetArrowWriterPropertiesBuilder <- R6Class("ParquetArrowWriterPropertiesBuilder", inherit = ArrowObject,
  public = list(
    store_schema = function() {
      parquet___ArrowWriterProperties___Builder__store_schema(self)
      self
    },
    set_int96_support = function(use_deprecated_int96_timestamps = FALSE) {
      if (use_deprecated_int96_timestamps) {
        parquet___ArrowWriterProperties___Builder__enable_deprecated_int96_timestamps(self)
      } else {
        parquet___ArrowWriterProperties___Builder__disable_deprecated_int96_timestamps(self)
      }
      self
    },
    set_coerce_timestamps = function(coerce_timestamps = NULL) {
      if (!is.null(coerce_timestamps)) {
        unit <- make_valid_time_unit(coerce_timestamps,
          c("ms" = TimeUnit$MILLI, "us" = TimeUnit$MICRO)
        )
        parquet___ArrowWriterProperties___Builder__coerce_timestamps(unit)
      }
      self
    },
    set_allow_truncated_timestamps = function(allow_truncated_timestamps = FALSE) {
      if (allow_truncated_timestamps) {
        parquet___ArrowWriterProperties___Builder__allow_truncated_timestamps(self)
      } else {
        parquet___ArrowWriterProperties___Builder__disallow_truncated_timestamps(self)
      }

      self
    }

  )
)
ParquetArrowWriterProperties <- R6Class("ParquetArrowWriterProperties", inherit = ArrowObject)

ParquetArrowWriterProperties$create <- function(use_deprecated_int96_timestamps = FALSE, coerce_timestamps = NULL, allow_truncated_timestamps = FALSE) {
  builder <- shared_ptr(ParquetArrowWriterPropertiesBuilder, parquet___ArrowWriterProperties___Builder__create())
  builder$store_schema()
  builder$set_int96_support(use_deprecated_int96_timestamps)
  builder$set_coerce_timestamps(coerce_timestamps)
  builder$set_allow_truncated_timestamps(allow_truncated_timestamps)
  shared_ptr(ParquetArrowWriterProperties, parquet___ArrowWriterProperties___Builder__build(builder))
}

valid_parquet_version <- c(
  "1.0" = ParquetVersionType$PARQUET_1_0,
  "2.0" = ParquetVersionType$PARQUET_2_0
)

make_valid_version <- function(version, valid_versions = valid_parquet_version) {
  if (is_integerish(version)) {
    version <- as.character(version)
  }
  tryCatch(
    valid_versions[[match.arg(version, choices = names(valid_versions))]],
    error = function(cond) {
      stop('"version" should be one of ', oxford_paste(names(valid_versions), "or"), call.=FALSE)
    }
  )
}

#' @title ParquetWriterProperties class
#' @rdname ParquetWriterProperties
#' @name ParquetWriterProperties
#' @docType class
#' @usage NULL
#' @format NULL
#' @description This class holds settings to control how a Parquet file is read
#' by [ParquetFileWriter].
#'
#' @section Factory:
#'
#' The `ParquetWriterProperties$create()` factory method instantiates the object
#' and takes the following arguments:
#'
#' - `table`: table to write (required)
#' - `version`: Parquet version, "1.0" or "2.0". Default "1.0"
#' - `compression`: Compression type, algorithm `"uncompressed"`
#' - `compression_level`: Compression level; meaning depends on compression algorithm
#' - `use_dictionary`: Specify if we should use dictionary encoding. Default `TRUE`
#' - `write_statistics`: Specify if we should write statistics. Default `TRUE`
#' - `data_page_size`: Set a target threshold for the approximate encoded
#'    size of data pages within a column chunk (in bytes). Default 1 MiB.
#'
#' @details The parameters `compression`, `compression_level`, `use_dictionary`
#'   and write_statistics` support various patterns:
#'
#'  - The default `NULL` leaves the parameter unspecified, and the C++ library
#'    uses an appropriate default for each column (defaults listed above)
#'  - A single, unnamed, value (e.g. a single string for `compression`) applies to all columns
#'  - An unnamed vector, of the same size as the number of columns, to specify a
#'    value for each column, in positional order
#'  - A named vector, to specify the value for the named columns, the default
#'    value for the setting is used when not supplied
#'
#' Unlike the high-level [write_parquet], `ParquetWriterProperties` arguments
#' use the C++ defaults. Currently this means "uncompressed" rather than
#' "snappy" for the `compression` argument.
#'
#' @seealso [write_parquet]
#'
#' @export
ParquetWriterProperties <- R6Class("ParquetWriterProperties", inherit = ArrowObject)
ParquetWriterPropertiesBuilder <- R6Class("ParquetWriterPropertiesBuilder", inherit = ArrowObject,
  public = list(
    set_version = function(version) {
      parquet___ArrowWriterProperties___Builder__version(self, make_valid_version(version))
    },

    set_compression = function(table, compression){
      private$.set(table, compression_from_name(compression), "compression", is.integer,
        parquet___ArrowWriterProperties___Builder__default_compression,
        parquet___ArrowWriterProperties___Builder__set_compressions
      )
    },

    set_compression_level = function(table, compression_level){
      private$.set(table, compression_level, "compression_level", is_integerish,
        parquet___ArrowWriterProperties___Builder__default_compression_level,
        parquet___ArrowWriterProperties___Builder__set_compression_levels
      )
    },

    set_dictionary = function(table, use_dictionary) {
      private$.set(table, use_dictionary, "use_dictionary", is.logical,
        parquet___ArrowWriterProperties___Builder__default_use_dictionary,
        parquet___ArrowWriterProperties___Builder__set_use_dictionary
      )
    },

    set_write_statistics = function(table, write_statistics) {
      private$.set(table, write_statistics, "write_statistics", is.logical,
        parquet___ArrowWriterProperties___Builder__default_write_statistics,
        parquet___ArrowWriterProperties___Builder__set_write_statistics
      )
    },

    set_data_page_size = function(data_page_size) {
      parquet___ArrowWriterProperties___Builder__data_page_size(self, data_page_size)
    }
  ),

  private = list(
    .set = function(table, value, name, is, default, multiple) {
      msg <- paste0("unsupported ", name, "= specification")
      assert_that(is(value), msg = msg)
      column_names <- names(table)
      if (is.null(given_names <- names(value))) {
        if (length(value) == 1L) {
          default(self, value)
        } else if (length(value) == length(column_names)) {
          multiple(self, column_names, value)
        }
      } else if(all(given_names %in% column_names)) {
        multiple(self, given_names, value)
      } else {
        abort(msg)
      }
    }
  )

)

ParquetWriterProperties$create <- function(table, version = NULL, compression = NULL, compression_level = NULL, use_dictionary = NULL, write_statistics = NULL, data_page_size = NULL) {
  if (is.null(version) && is.null(compression) && is.null(compression_level) && is.null(use_dictionary) && is.null(write_statistics) && is.null(data_page_size)) {
    shared_ptr(ParquetWriterProperties, parquet___default_writer_properties())
  } else {
    builder <- shared_ptr(ParquetWriterPropertiesBuilder, parquet___WriterProperties___Builder__create())
    if (!is.null(version)) {
      builder$set_version(version)
    }
    if (!is.null(compression)) {
      builder$set_compression(table, compression = compression)
    }
    if (!is.null(compression_level)) {
      builder$set_compression_level(table, compression_level = compression_level)
    }
    if (!is.null(use_dictionary)) {
      builder$set_dictionary(table, use_dictionary)
    }
    if (!is.null(write_statistics)) {
      builder$set_write_statistics(table, write_statistics)
    }
    if (!is.null(data_page_size)) {
      builder$set_data_page_size(data_page_size)
    }
    shared_ptr(ParquetWriterProperties, parquet___WriterProperties___Builder__build(builder))
  }
}

#' @title ParquetFileWriter class
#' @rdname ParquetFileWriter
#' @name ParquetFileWriter
#' @docType class
#' @usage NULL
#' @format NULL
#' @description This class enables you to interact with Parquet files.
#'
#' @section Factory:
#'
#' The `ParquetFileWriter$create()` factory method instantiates the object and
#' takes the following arguments:
#'
#' - `schema` A [Schema]
#' - `sink` An [arrow::io::OutputStream][OutputStream] or a string which is interpreted as a file path
#' - `properties` An instance of [ParquetWriterProperties]
#' - `arrow_properties` An instance of `ParquetArrowWriterProperties`
#' @export
#' @include arrow-package.R
ParquetFileWriter <- R6Class("ParquetFileWriter", inherit = ArrowObject,
  public = list(
    WriteTable = function(table, chunk_size) {
      parquet___arrow___FileWriter__WriteTable(self, table, chunk_size)
    },
    Close = function() {
      parquet___arrow___FileWriter__Close(self)
    }
  )

)
ParquetFileWriter$create <- function(
  schema,
  sink,
  properties = ParquetWriterProperties$create(),
  arrow_properties = ParquetArrowWriterProperties$create()
) {
  unique_ptr(
    ParquetFileWriter,
    parquet___arrow___ParquetFileWriter__Open(schema, sink, properties, arrow_properties)
  )
}


#' @title ParquetFileReader class
#' @rdname ParquetFileReader
#' @name ParquetFileReader
#' @docType class
#' @usage NULL
#' @format NULL
#' @description This class enables you to interact with Parquet files.
#'
#' @section Factory:
#'
#' The `ParquetFileReader$create()` factory method instantiates the object and
#' takes the following arguments:
#'
#' - `file` A character file name, raw vector, or Arrow file connection object
#'    (e.g. `RandomAccessFile`).
#' - `props` Optional [ParquetReaderProperties]
#' - `mmap` Logical: whether to memory-map the file (default `TRUE`)
#' - `...` Additional arguments, currently ignored
#'
#' @section Methods:
#'
#' - `$ReadTable(col_select)`: get an `arrow::Table` from the file, possibly
#'    with columns filtered by a character vector of column names or a
#'    `tidyselect` specification.
#' - `$GetSchema()`: get the `arrow::Schema` of the data in the file
#'
#' @export
#' @examples
#' \donttest{
#' f <- system.file("v0.7.1.parquet", package="arrow")
#' pq <- ParquetFileReader$create(f)
#' pq$GetSchema()
#' tab <- pq$ReadTable(starts_with("c"))
#' tab$schema
#' }
#' @include arrow-package.R
ParquetFileReader <- R6Class("ParquetFileReader",
  inherit = ArrowObject,
  active = list(
    num_rows = function() {
      as.integer(parquet___arrow___FileReader__num_rows(self))
    }
  ),
  public = list(
    ReadTable = function(col_select = NULL) {
      col_select <- enquo(col_select)
      if (quo_is_null(col_select)) {
        shared_ptr(Table, parquet___arrow___FileReader__ReadTable1(self))
      } else {
        all_vars <- shared_ptr(Schema, parquet___arrow___FileReader__GetSchema(self))$names
        indices <- match(vars_select(all_vars, !!col_select), all_vars) - 1L
        shared_ptr(Table, parquet___arrow___FileReader__ReadTable2(self, indices))
      }
    },
    GetSchema = function() {
      shared_ptr(Schema, parquet___arrow___FileReader__GetSchema(self))
    }
  )
)

ParquetFileReader$create <- function(file,
                                     props = ParquetReaderProperties$create(),
                                     mmap = TRUE,
                                     ...) {
  file <- make_readable_file(file, mmap)
  assert_is(props, "ParquetReaderProperties")

  unique_ptr(ParquetFileReader, parquet___arrow___FileReader__OpenFile(file, props))
}

#' @title ParquetReaderProperties class
#' @rdname ParquetReaderProperties
#' @name ParquetReaderProperties
#' @docType class
#' @usage NULL
#' @format NULL
#' @description This class holds settings to control how a Parquet file is read
#' by [ParquetFileReader].
#'
#' @section Factory:
#'
#' The `ParquetReaderProperties$create()` factory method instantiates the object
#' and takes the following arguments:
#'
#' - `use_threads` Logical: whether to use multithreading (default `TRUE`)
#'
#' @section Methods:
#'
#' - `$read_dictionary(column_index)`
#' - `$set_read_dictionary(column_index, read_dict)`
#' - `$use_threads(use_threads)`
#'
#' @export
ParquetReaderProperties <- R6Class("ParquetReaderProperties",
  inherit = ArrowObject,
  public = list(
    read_dictionary = function(column_index) {
      parquet___arrow___ArrowReaderProperties__get_read_dictionary(self, column_index)
    },
    set_read_dictionary = function(column_index, read_dict) {
      parquet___arrow___ArrowReaderProperties__set_read_dictionary(self, column_index, read_dict)
    }
  ),
  active = list(
    use_threads = function(use_threads) {
      if(missing(use_threads)) {
        parquet___arrow___ArrowReaderProperties__get_use_threads(self)
      } else {
        parquet___arrow___ArrowReaderProperties__set_use_threads(self, use_threads)
      }
    }
  )
)

ParquetReaderProperties$create <- function(use_threads = option_use_threads()) {
  shared_ptr(
    ParquetReaderProperties,
    parquet___arrow___ArrowReaderProperties__Make(isTRUE(use_threads))
  )
}
