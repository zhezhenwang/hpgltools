#' Pull metadata from a table (xlsx/xls/csv/whatever)
#'
#' I find that when I acquire metadata from a paper or collaborator, annoyingly
#' often there are many special characters or other shenanigans in the column
#' names.  This function performs some simple sanitizations.  In addition, if I
#' give it a filename it calls my generic 'read_metadata()' function before
#' sanitizing.
#'
#' @param metadata file or df of metadata
#' @param id_column Column in the metadat containing the sample names.
#' @param ... Arguments to pass to the child functions (read_csv etc).
#' @return Metadata dataframe hopefully cleaned up to not be obnoxious.
#' @examples
#'  \dontrun{
#'   sanitized <- extract_metadata("some_random_supplemental.xls")
#'   saniclean <- extract_metadata(some_goofy_df)
#' }
#' @export
extract_metadata <- function(metadata, id_column = "sampleid", ...) {
  arglist <- list(...)
  ## FIXME: Now that this has been yanked into its own function,
  ## Make sure it sets good, standard rownames.
  file <- NULL

  meta_dataframe <- NULL
  meta_file <- NULL
  if ("character" %in% class(metadata)) {
    ## This is a filename containing the metadata
    meta_file <- metadata
  } else if ("data.frame" %in% class(metadata)) {
    ## A data frame of metadata was passed.
    meta_dataframe <- metadata
  } else {
    stop("This requires either a file or meta data.frame.")
  }

  ## The two primary inputs for metadata are a csv/xlsx file or a dataframe, check for them here.
  if (is.null(meta_dataframe) & is.null(meta_file)) {
    stop("This requires either a csv file or dataframe of metadata describing the samples.")
  } else if (is.null(meta_file)) {
    ## punctuation is the devil
    sample_definitions <- meta_dataframe
  }  else {
    sample_definitions <- read_metadata(meta_file,
                                        ...)
    ## sample_definitions <- read_metadata(meta_file)
  }

  colnames(sample_definitions) <- gsub(pattern = "[[:punct:]]",
                                       replacement = "",
                                       x = colnames(sample_definitions))
  id_column <- tolower(id_column)
  id_column <- gsub(pattern = "[[:punct:]]",
                    replacement = "",
                    x = id_column)

  ## Get appropriate row and column names.
  current_rownames <- rownames(sample_definitions)
  bad_rownames <- as.character(1:nrow(sample_definitions))
  ## Try to ensure that we have a useful ID column by:
  ## 1. Look for data in the id_column column.
  ##  a.  If it is null, look at the rownames
  ##    i.  If they are 1...n, arbitrarily grab the first column.
  ##    ii. If not, use the rownames.
  if (is.null(sample_definitions[[id_column]])) {
    if (identical(current_rownames, bad_rownames)) {
      id_column <- colnames(sample_definitions)[1]
    } else {
      sample_definitions[[id_column]] <- rownames(sample_definitions)
    }
  }

  ## Drop empty rows in the sample sheet
  empty_samples <- which(sample_definitions[, id_column] == "" |
                         grepl(x = sample_definitions[, id_column], pattern = "^undef") |
                         is.na(sample_definitions[, id_column]) |
                         grepl(pattern = "^#", x = sample_definitions[, id_column]))
  if (length(empty_samples) > 0) {
    message("Dropped ", length(empty_samples),
            " rows from the sample metadata because they were blank.")
    sample_definitions <- sample_definitions[-empty_samples, ]
  }

  ## Drop duplicated elements.
  num_duplicated <- sum(duplicated(sample_definitions[[id_column]]))
  if (num_duplicated > 0) {
    message("There are ", num_duplicated,
            " duplicate rows in the sample ID column.")
    sample_definitions[[id_column]] <- make.names(sample_definitions[[id_column]],
                                                  unique = TRUE)
  }

  ## Now we should have consistent sample IDs, set the rownames.
  rownames(sample_definitions) <- sample_definitions[[id_column]]
  ## Check that condition and batch have been filled in.
  sample_columns <- colnames(sample_definitions)

  ## The various proteomics data I am looking at annoyingly starts with a number
  ## So make.names() prefixes it with X which is ok as far as it goes, but
  ## since it is a 's'amplename, I prefer an 's'.
  rownames(sample_definitions) <- gsub(pattern = "^X([[:digit:]])",
                                       replacement = "s\\1",
                                       x = rownames(sample_definitions))

  sample_columns_to_remove <- NULL
  for (col in 1:length(colnames(sample_definitions))) {
    sum_na <- sum(is.na(sample_definitions[[col]]))
    sum_null <- sum(is.null(sample_definitions[[col]]))
    sum_empty <- sum_na + sum_null
    if (sum_empty ==  nrow(sample_definitions)) {
      ## This column is empty.
      sample_columns_to_remove <- append(sample_columns_to_remove, col)
    }
  }
  if (length(sample_columns_to_remove) > 0) {
    sample_definitions <- sample_definitions[-sample_columns_to_remove]
  }

  ## Now check for columns named condition and batch
  found_condition <- "condition" %in% sample_columns
  if (!isTRUE(found_condition)) {
    message("Did not find the condition column in the sample sheet.")
    message("Filling it in as undefined.")
    sample_definitions[["condition"]] <- "undefined"
  } else {
    ## Make sure there are no NAs in this column.
    na_idx <- is.na(sample_definitions[["condition"]])
    sample_definitions[na_idx, "condition"] <- "undefined"
  }
  found_batch <- "batch" %in% sample_columns
  if (!isTRUE(found_batch)) {
    message("Did not find the batch column in the sample sheet.")
    message("Filling it in as undefined.")
    sample_definitions[["batch"]] <- "undefined"
  } else {
    ## Make sure there are no NAs in this column.
    na_idx <- is.na(sample_definitions[["batch"]])
    sample_definitions[na_idx, "batch"] <- "undefined"
  }

  ## Double-check that there is a usable condition column
  ## This is also an instance of simplifying subsetting, identical to
  ## sample_definitions[["condition"]] I don't think I care one way or the other which I use in
  ## this case, just so long as I am consistent -- I think because I have trouble remembering the
  ## difference between the concept of 'row' and 'column' I should probably use the [, column] or
  ## [row, ] method to reinforce my weak neurons.
  if (is.null(sample_definitions[["condition"]])) {
    ## type and stage are commonly used, and before I was consistent about always having
    ## condition, they were a proxy for it.
    sample_definitions[["condition"]] <- tolower(paste(sample_definitions[["type"]],
                                                       sample_definitions[["stage"]], sep = "_"))
  }
  ## Extract out the condition names as a factor
  condition_names <- unique(sample_definitions[["condition"]])
  if (is.null(condition_names)) {
    warning("There is no 'condition' field in the definitions, this will make many
analyses more difficult/impossible.")
  }
  ## Condition and Batch are not allowed to be numeric, so if they are just numbers,
  ## prefix them with 'c' and 'b' respectively.
  pre_condition <- unique(sample_definitions[["condition"]])
  pre_batch <- unique(sample_definitions[["batch"]])
  sample_definitions[["condition"]] <- gsub(pattern = "^(\\d+)$", replacement = "c\\1",
                                            x = sample_definitions[["condition"]])
  sample_definitions[["batch"]] <- gsub(pattern = "^(\\d+)$", replacement = "b\\1",
                                        x = sample_definitions[["batch"]])
  sample_definitions[["condition"]] <- factor(sample_definitions[["condition"]],
                                              levels = unique(sample_definitions[["condition"]]),
                                              labels = pre_condition)
  sample_definitions[["batch"]] <- factor(sample_definitions[["batch"]],
                                          levels = unique(sample_definitions[["batch"]]),
                                          labels = pre_batch)
  return(sample_definitions)
}


gather_preprocessing_metadata <- function(starting_metadata, specification = NULL,
                                          new_metadata = NULL, verbose = FALSE, ...) {
  if (is.null(specification)) {
    specification <- list(
        "trimomatic_input" = list(
            "file" = "preprocessing/{meta[['sampleid']]}/outputs/*-trimomatic.out"),
        "trimomatic_output" = list(
            "file" = "preprocessing/{meta[['sampleid']]}/outputs/*-trimomatic.out"),
        "trimomatic_ratio" = list(
            "column" = "trimomatic_percent"),
        "hisat_single_concordant" = list(
            "file" = "preprocessing/{meta[['sampleid']]}/outputs/hisat2_{species}/hisat2_*.err"),
        "hisat_multi_concordant" = list(
            "file" = "preprocessing/{meta[['sampleid']]}/outputs/hisat2_{species}/hisat2_*.err"),
        "hisat_single_all" = list(
            "file" = "preprocessing/{meta[['sampleid']]}/outputs/hisat2_{species}/hisat2_*.err"),
        "hisat_multi_all" = list(
            "file" = "preprocessing/{meta[['sampleid']]}/outputs/hisat2_{species}/hisat2_*.err"),
        "hisat_singlecon_ratio" = list(
            "column" = "hisat_single_concordant_percent"),
        "hisat_singleall_ratio" = list(
            "column" = "hisat_single_all_percent"
        )        
    )
    
  }
  if (is.null(new_metadata)) {
    new_metadata <- gsub(x = starting_metadata, pattern = "\\.xlsx$",
                         replacement = "_modified.xlsx")
  }

  meta <- extract_metadata(starting_metadata)
  for (entry in 1:length(specification)) {
    entry_type <- names(specification[entry])
    new_column <- entry_type
    if (!is.null(specification[[entry_type]][["column"]])) {
      new_column <- specification[[entry_type]][["column"]]
    }
    if (new_column %in% colnames(meta)) {
      warning("Column: ", new_column, " already exists, replacing it.")
    }
    input_file_spec <- specification[[entry_type]][["file"]]
    meta[[new_column]] <- dispatch_metadata_extract(meta, entry_type,
                                                    input_file_spec,
                                                    specification,
                                                    verbose = verbose,
                                                    ...)
  }
  message("Writing new metadata to: ", new_metadata)
  written <- write_xlsx(data = meta, excel = new_metadata)
  return(new_metadata)
}

dispatch_metadata_extract <- function(meta, entry_type, input_file_spec,
                                      specification, verbose = FALSE, ...) {
  switchret <- switch(
      entry_type,
      "trimomatic_input" = {
        search <- "^Input Read Pairs: \\d+ .*$"
        replace <- "^Input Read Pairs: (\\d+) .*$"
        entries <- dispatch_regex_search(meta, search, replace,
                                         input_file_spec, verbose = verbose,
                                         ...)
      },
      "trimomatic_output" = {
        search <- "^Input Read Pairs: \\d+ Both Surviving: \\d+ .*$"
        replace <- "^Input Read Pairs: \\d+ Both Surviving: (\\d+) .*$"
        entries <- dispatch_regex_search(meta, search, replace,
                                         input_file_spec, verbose = verbose,
                                         ...)
      },
      "trimomatic_ratio" = {
        ## I think we can assume that the trimomatic ratio will come immediately after input/output
        numerator_column <- "trimomatic_output"
        if (!is.null(specification[["trimomatic_output"]][["column"]])) {
          numerator_column <- specification[["trimomatic_output"]][["column"]]
        }
        denominator_column <- "trimomatic_input"
        if (!is.null(specification[["trimomatic_input"]][["column"]])) {
          denominator_column <- specification[["trimomatic_input"]][["column"]]
        }
        entries <- dispatch_metadata_ratio(meta, numerator_column,
                                           denominator_column, verbose = verbose)
      },
      "hisat_single_concordant" = {
        search <-"^\\s+\\d+ \\(.+\\) aligned concordantly exactly 1 time" 
        replace <- "^\\s+(\\d+) \\(.+\\) aligned concordantly exactly 1 time"
        entries <- dispatch_regex_search(meta, search, replace,
                                         input_file_spec, verbose = verbose,
                                         ...)
      },
      "hisat_multi_concordant" = {
        search <- "^\\s+\\d+ \\(.+\\) aligned concordantly >1 times"
        replace <- "^\\s+(\\d+) \\(.+\\) aligned concordantly >1 times"
        entries <- dispatch_regex_search(meta, search, replace,
                                         input_file_spec, verbose = verbose,
                                         ...)
      },
      "hisat_single_all" = {
        search <- "^\\s+\\d+ \\(.+\\) aligned exactly 1 time"
        replace <- "^\\s+(\\d+) \\(.+\\) aligned exactly 1 time"
        entries <- dispatch_regex_search(meta, search, replace,
                                         input_file_spec, verbose = verbose,
                                         ...)
      },
      "hisat_multi_all" = {
        search <- "^\\s+\\d+ \\(.+\\) aligned concordantly >1 times"
        replace <- "^\\s+(\\d+) \\(.+\\) aligned concordantly >1 times"
        entries <- dispatch_regex_search(meta, search, replace,
                                         input_file_spec, verbose = verbose,
                                         ...)
      },
      "hisat_singlecon_ratio" = {
        numerator_column <- specification[["hisat_single_concordant"]][["column"]]
        denominator_column <- specification[["trimomatic_input"]][["column"]]
        entries <- dispatch_metadata_ratio(meta, numerator_column, denominator_column)
      },
      "hisat_singleall_ratio" = {
        numerator_column <- "hisat_single_all"
        if (!is.null(specification[["hisat_single_all"]][["column"]])) {
          numerator_column <- specification[["hisat_single_all"]][["column"]]
        }
        denominator_column <- "trimomatic_input"
        if (!is.null(specification[["trimomatic_input"]][["column"]])) {
          denominator_column <- specification[["trimomatic_input"]][["column"]]
        }
        entries <- dispatch_metadata_ratio(meta, numerator_column, denominator_column)
      },
      {
        stop("I do not know this spec: ", entry_type)
      })
  return(entries)
}

dispatch_metadata_ratio <- function(meta, numerator_column = NULL,
                                    denominator_column = NULL, verbose = FALSE) {
  column_number <- ncol(meta)
  if (is.null(numerator_column)) {
    numerator_column <- colnames(meta)[ncol(meta)]
  }
  if (is.null(denominator_column)) {
    denominator_column <- colnames(meta)[ncol(meta) - 1]
  }
  message("The numerator column is: ", numerator_column, ".")
  message("The denominator column is: ", denominator_column, ".")
  entries <- as.numeric(meta[[numerator_column]]) / as.numeric(meta[[denominator_column]])
  return(entries)
}

dispatch_regex_search <- function(meta, search, replace,
                                  input_file_spec, verbose = FALSE,
                                  ...) {
  arglist <- list(...)
  ##if (length(arglist) > 0) {
  ##  
  ##}
  filenames_with_wildcards <- glue::glue(input_file_spec, ...)
  message("Example filename: ", filenames_with_wildcards[1], ".")
  output_entries <- rep(0, length(filenames_with_wildcards))
  for (row in 1:nrow(meta)) {
    input_file <- Sys.glob(filenames_with_wildcards[row])
    input_handle <- file(input_file, "r", blocking = FALSE)
    input_vector <- readLines(input_handle)
    for (i in 1:length(input_vector)) {
      input_line <- input_vector[i]
      if (grepl(x = input_line, pattern = search)) {
        if (isTRUE(verbose)) {
          message("Found the correct line: ")
          message(input_line)
        }                  
        output_entries[row] <- gsub(x = input_line,
                                    pattern = replace,
                                    replacement = "\\1")
      } else {
        next
      }
    } ## End looking at every line of the log file specified by the input file spec for this row
    close(input_handle)
  } ## End looking at every row of the metadata
  return(output_entries)
}

sanitize_expt_metadata <- function(expt, columns = NULL, na_string = "notapplicable") {
  pd <- pData(expt)
  if (is.null(columns)) {
    columns <- colnames(pd)
  }
  for (col in 1:length(columns)) {
    todo <- columns[col]
    mesg("Sanitizing metadata column: ", todo, ".")
    if (! todo %in% colnames(pd)) {
      mesg("The column ", todo, " is missing, skipping it (also warning this).")
      warning("The column ", todo, " is missing, skipping it.")
      next
    }
      
    ## First get rid of trailing/leading spaces, those anger me and are crazy hard to find
    pd[[todo]] <- gsub(pattern = "^[[:space:]]", replacement = "", x = pd[[todo]])
    pd[[todo]] <- gsub(pattern = "[[:space:]]$", replacement = "", x = pd[[todo]])
    ## Set the column to lowercase, I have recently had a rash of mixed case sample sheet columns.
    pd[[todo]] <- tolower(pd[[todo]])
    ## I think punctuation needs to go
    pd[[todo]] <- gsub(pattern = "[[:punct:]]", replacement = "", x = pd[[todo]])

    ## Set NAs to "NotApplicable"
    na_idx <- is.na(pd[[todo]])
    pd[na_idx, todo] <- na_string
  }
  pData(expt[["expressionset"]]) <- pd
  expt[["design"]] <- pd
  return(expt)
}

## EOF
