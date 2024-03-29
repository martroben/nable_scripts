#!/usr/bin/env Rscript


#######################################################################################################
##                                                                                                   ##
##  Script name: backup_usage_script.R                                                               ##
##  Purpose of script: format and summarize data from N-able Backup & Recovery                       ##
##                     maximum value monthly usage report                                            ##
##  Author: Mart Roben                                                                               ##
##  Date Created: 29. Dec 2021                                                                       ##
##                                                                                                   ##
##  Copyright: BSD-3-Clause                                                                          ##
##  https://github.com/martroben/nable_scripts                                                       ##
##                                                                                                   ##
##  Contact: mart@altacom.eu                                                                         ##
##                                                                                                   ##
#######################################################################################################


#################
# Load packages #
#################

# Cleaning the environment (to avoid conflicts with objects from previous session)
rm(list = ls(all.names = TRUE))

# Installing & loading necessary packages
if (!require("pacman", quietly = TRUE)) install.packages("pacman")
pacman::p_load("magrittr",
               "dplyr",
               "stringr",
               "purrr",
               "openxlsx",
               "readxl",
               "argparser",
               "rlang")



#########
# Input #
#########

backup_usage_xlsx_default <- "C:/Temp/bu_usage_report.xlsx"
export_xlsx_default <- "C:/Temp/bu_usage_companies.xlsx"

p <- argparser::arg_parser("This script extracts individual customer usages from the N-able Backup & Recovery maximum value monthly usage report.", hide.opts = TRUE)
p <- argparser::add_argument(p, "--usage", help = "Usage report xlsx full path.", default = backup_usage_xlsx_default)
p <- argparser::add_argument(p, "--out_xlsx", help = "Output xlsx full path.", default = export_xlsx_default)

input_args <- argparser::parse_args(p)

backup_usage_xlsx_path <- input_args$usage
export_xlsx_path <- input_args$out_xlsx



#############
# Functions #
#############

# Format and summarize usage data
get_bu_usage <- function(usedata, partner) {
  
  usedata %>% dplyr::filter(Parent1Name == partner) %>%
    dplyr::group_by(CustomerName) %>%
    dplyr::summarise(Serv = sum(OsType == "Server"),
                     Ws = sum(OsType == "Workstation"),
                     Unknown = sum(!(OsType %in% c("Server", "Workstation"))),
                     SelectedSizeGb = sum(DeviceSelectedSizeGb),
                     RecTest = sum(RecoveryTesting == "true"),
                     M365Users = sum(O365Users),
                     M365SizeGb = sum(M365SelectedSizeGb))
}


# General xlsx exporting function
export_xlsx_general <- function(export_data, export_path) {
  
  xlsx_workbook <- openxlsx::createWorkbook()
  addWorksheet(xlsx_workbook, sheetName = "Sheet1")
  
  # write export data to worksheet
  openxlsx::writeData(wb = xlsx_workbook,
                      sheet = "Sheet1",
                      x = export_data)
  
  openxlsx::setColWidths(wb = xlsx_workbook,
                         sheet = "Sheet1",
                         cols = 1:ncol(export_data),
                         widths = "auto")
  
  openxlsx::saveWorkbook(wb = xlsx_workbook, 
                         file = export_path,
                         overwrite = TRUE)
}



#############
# Execution #
#############

rlang::inform("Loading xlsx...")
bu_usedata_raw <- readxl::read_xlsx(path = backup_usage_xlsx_path)


rlang::inform("Formatting report data...")
bu_usedata <- bu_usedata_raw %>%
    dplyr::filter(CustomerState == "InProduction") %>%
    dplyr::mutate(
      
      Parent2Name = dplyr::case_when(
        is.na(Parent2Name) ~ Parent1Name,
        TRUE ~ Parent2Name
      ),
      
      Parent1Name = dplyr::case_when(
        Parent1Name == "Altacom" ~ CustomerName,
        TRUE ~ Parent1Name
      ),
      
      OsType = dplyr::case_when(
        is.na(OsType) ~ CurrentMonthMvSKU,
        TRUE ~ OsType
      ),
      
      DeviceSelectedSizeGb = dplyr::case_when(
        O365Users == 0 ~ SelectedSizeGb,
        TRUE ~ 0
      ),
      
      M365SelectedSizeGb = dplyr::case_when(
        O365Users > 0 ~ SelectedSizeGb,
        TRUE ~ 0
      )) %>%

    dplyr::select(Parent1Name,
                  CustomerName,
                  OsType,
                  DeviceName,
                  O365Users,
                  DeviceSelectedSizeGb,
                  M365SelectedSizeGb, 
                  RecoveryTesting)

partner_name <- unique(bu_usedata$Parent1Name)
bu_usedata_sorted <- get_bu_usage(bu_usedata, partner_name)

bu_usedata_export <- bu_usedata_sorted %>%
    dplyr::mutate(SelectedSizeGb = SelectedSizeGb %>% round(2),
                      M365SizeGb = M365SizeGb %>% round(2)) %>%
    dplyr::select(-Unknown) %>%
    purrr::when(sum(.$RecTest, na.rm = TRUE) == 0 ~ dplyr::select(., -RecTest),
                                                  ~ .) %>%
    purrr::when(sum(.$M365Users, na.rm = TRUE) == 0 ~ dplyr::select(., -M365Users, -M365SizeGb),
                                                    ~ .)


rlang::inform("Exporting xlsx...")
export_xlsx_general(bu_usedata_export, export_xlsx_path)


rlang::inform(stringr::str_c("Output xlsx created at ", export_xlsx_path))
