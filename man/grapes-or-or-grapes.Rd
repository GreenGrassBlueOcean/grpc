% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ProtoParser.R, R/client.R
\name{\%||\%}
\alias{\%||\%}
\title{Default Value for NULL}
\usage{
x \%||\% y

x \%||\% y
}
\arguments{
\item{x}{The value to test.}

\item{y}{The default value to return if \code{x} is \code{NULL}.}

\item{a}{The object to test for `NULL`.}

\item{b}{The default value to return if `a` is `NULL`.}
}
\value{
Returns `a` if it is not `NULL`, otherwise returns `b`.

\code{x} if it is not \code{NULL}, otherwise \code{y}.
}
\description{
This operator returns the right-hand side of the expression if the left-hand
side is `NULL`. It is a convenient shorthand for `if (is.null(x)) y else x`.

This operator is often called the "null coalescing" or "null default" operator.

This infix operator returns the right-hand side \code{y} if the
left-hand side \code{x} is \code{NULL}; otherwise, it returns \code{x}.
}
\examples{
# Basic usage
x <- NULL
y <- 42

x \%||\% "default" # Returns "default"
y \%||\% "default" # Returns 42

# Common use case in a function
configure_settings <- function(settings = NULL) {
  default_settings <- list(theme = "dark", notifications = TRUE)
  final_settings <- settings \%||\% default_settings
  return(final_settings)
}

# No settings provided, so defaults are used
configure_settings()

# User provides custom settings
configure_settings(list(theme = "light"))
NULL \%||\% 5 # Returns 5
10 \%||\% 5   # Returns 10

my_var <- NULL
value <- my_var \%||\% "default_string"
print(value) # "default_string"

my_var2 <- list(a = 1)
value2 <- my_var2 \%||\% list()
print(value2) # list(a = 1)
}
