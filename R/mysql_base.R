# roxygen2::roxygenise()

simplifyText <- function(text) {
  text = tolower(text)
  text = gsub("\r|\n|\t", "", text)
  text = gsub("(", "", text, fixed=TRUE)
  text = gsub(")", "", text, fixed=TRUE)
  text = gsub(" ", "", text, fixed=TRUE)
  return (text)
}

multiplelines.message <- function (strText) {
  # writeLines(strwrap(strText, width=73))
  # strText = unlist(strsplit(strText, "\r\n"))
  strText = unlist(strsplit(strText, "\n"))
  for (line in strText) message(line)
}

isSelect <- function(text) {
  text = simplifyText(text)
  return ((substr(text, 1, 6) == "select") || (text == "show tables") || (text == "show schemas"))
}

#' @title ms.connect
#' @export
ms.connect <- function (
  host,
  port = "3306",
  schema = NULL,
  user = connData$IAM_user,
  pass = connData$IAM_pass,
  ssl_ca_params = connData$db_mysql_ssl_ca_params,
  use_ssl = !is.null(connData$db_mysql_ssl_ca_params),
  jar = system.file("java", "mysql-connector-java-5.1.40-bin.jar", package = "mysqltools")
) {
  if (use_log) multiplelines.message(paste0("[Query Time]: ",format(Sys.time(), "%Y%m%d_%H_%M_%S"),"\n"))
  if (use_log) multiplelines.message(paste0("[Query Input]:\n Connect \n"))

  option_mysql_driver = getOption("mysql_driver")
  if (is.null(option_mysql_driver)) {
    if (use_JDBC) {
      option_mysql_driver = "RJDBC"
    } else {
      option_mysql_driver = "RMariaDB"
    }
  }

  if (option_mysql_driver == "RJDBC") {
    if (!requireNamespace("RJDBC", quietly = TRUE)) {
      stop("Package RJDBC needed for this function to work. Please install it.", call. = FALSE)
    }
    strParams = ""
    if (use_ssl) strParams = paste0("?verifyServerCertificate=false&useSSL=true&requireSSL=true&useOldAliasMetadataBehavior=true")

    drv <- RJDBC::JDBC(
      "com.mysql.jdbc.Driver",
      jar)

    ch <- dbConnect(
      drv,
      url = paste0("jdbc:mysql://",host,":",port,"/",schema,strParams),
      user = user,
      pass = pass)
  } else if (option_mysql_driver == "RMySQL") {
    drv <- RMySQL::MySQL()

    ch <- RMySQL::dbConnect(
      drv,
      user = user,
      password = pass,
      host = host,
      default.file = ssl_ca_params)
    if (tolower(Sys.info()['sysname']) != "windows") {
      dbGetQuery(ch,'SET NAMES utf8')
    }
  } else {
    if (Sys.info()["sysname"] != "Linux") {
      params_file = connData$db_mysql_ssl_ca_params
    } else {
      params_file = NULL
    }

    drv <- RMariaDB::MariaDB()

    ch <- dbConnect(
      drv = drv,
      username = user,
      password = pass,
      host = host,
      port = port,
      default.file = params_file,
      bigint = "numeric"
    )
  }
  if (!is.null(schema)) {
    if (use_log) multiplelines.message(paste0("[Query Time]: ",format(Sys.time(), "%Y%m%d_%H_%M_%S"),"\n"))
    if (use_log) multiplelines.message(paste0("[Query Input]:\n USE ",schema," \n"))
    DBI::dbSendQuery(ch, paste0("use ", schema))
  }
  return(ch)
}

#' @title ms.Use
#' @export
ms.Use <- function (
  ch,
  schema
) {
  if (use_log) multiplelines.message(paste0("[Query Time]: ",format(Sys.time(), "%Y%m%d_%H_%M_%S"),"\n"))
  if (use_log) multiplelines.message(paste0("[Query Input]:\n USe ",schema," \n"))
  DBI::dbSendQuery(ch, paste0("use ", schema))
}

#' @title ms.close
#' @export
ms.close <- function (ch = ch) {
  if (use_log) multiplelines.message(paste0("[Query Time]: ",format(Sys.time(), "%Y%m%d_%H_%M_%S"),"\n"))
  if (use_log) multiplelines.message(paste0("[Query Input]:\n Close Connection \n"))
  invisible(DBI::dbDisconnect(ch))
}

#' @title ms.Query
#' @export
ms.Query <- function(ch, query, asDataTable=mysqltools:::as.data.table.output, clearResulset=mysqltools:::clear.resulset, limit=-1) {
  if (use_log) multiplelines.message(paste0("[Query Time]: ",format(Sys.time(), "%Y%m%d_%H_%M_%S"),"\n"))
  if (use_log) multiplelines.message(paste0("[Query Input]:\n",query,"\n"))
  timer = proc.time()
  if (clearResulset) {
    ms.ClearResults(ch)
  }
  if (isSelect(query)) {
    if (limit>=0) query = paste0(query," limit ",limit)
    suppressWarnings({
    res <- DBI::dbSendQuery(ch, query)
    })
    df <- DBI::dbFetch(res, n=-1)
    DBI::dbClearResult(res)
  } else {
    DBI::dbSendQuery(ch, query)
    df = ""
  }
  timer = round(proc.time() - timer)
  if (class(df)=="character") {
    if (sum(nchar(df))>0)
      warning(paste0("[Query Output] Error:\n",paste0(df, collapse="\n")))
    else
      if (use_log) message(paste0("[Query Output] Ok: 0 rows returned.\n"))
  } else {
    if (use_log) message(paste0("[Query Output] Ok: ",nrow(df)," rows returned.\n"))
  }
  if (use_log) message(paste0("[Query Execution Time: ",timer[3]," seconds.]\n"))
  if (class(df)=="character" && sum(nchar(df))==0) {
    invisible(NULL)
  } else if (asDataTable && class(df)!="character") {
    return(data.table::as.data.table(df))
  } else {
    return(df)
  }
}

#' @title ms.ClearResults
#' @export
ms.ClearResults <- function(ch) {
  tryCatch({
    if (isTRUE(getOption("mysql_clear_results"))) {
      if (class(ch) != "JDBCConnection") {
        listResults = dbListResults(ch)
        if (length(listResults)>0) {
          if (use_log) message(paste0("[Clearing...]"))
          DBI::dbClearResult(dbListResults(ch)[[1]])
          if (use_log) message(paste0("[Cleared]"))
        }
      }
    }
  }, error = function(e) {warning(e)})
  invisible(NULL)
}

#' @title ms.Update
#' @export
ms.Update <- function(ch, query, clearResulset=mysqltools:::clear.resulset) {
  if (use_log) multiplelines.message(paste0("[Query Time]: ",format(Sys.time(), "%Y%m%d_%H_%M_%S"),"\n"))
  if (use_log) multiplelines.message(paste0("[Query Input (update)]:\n",query,"\n"))
  timer = proc.time()
  if (clearResulset) {
    ms.ClearResults(ch)
  }
  if (class(ch) == "JDBCConnection") {
    func_query = RJDBC::dbSendUpdate(ch, query)
  } else {
    func_query = dbGetQuery(ch, query)
  }
  timer = round(proc.time() - timer)
  if (use_log) message(paste0("[Query Execution Time: ",timer[3]," seconds.]\n"))
  invisible(return(func_query))
}
