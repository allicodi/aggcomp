#'
#' Function to do g-computation for antibiotics growth analysis
#' 
#' @param data dataframe containing dataset to use for gcomp
#' @param laz_var_name name of growth outcome variable
#' @param abx_var_name name of binary antibiotic variable
#' @param infection_var_name name of binary infection variable
#' @param severity_list character vector containing names of severity-related covariates (post-infection). If NULL, perform traditional gcomputation. Else, perform longitudinal gcomputation
#' @param covariate_list character vector containing names of baseline covariates
#' @param site_var_name name of site covariate in dataset (if applicable, else null)
#' @param site_interaction TRUE or FALSE indicating interaction between site and antibiotics 
#' @param age_var_name name of age covariate in dataset (if applicable, else NULL)
#' 
#' @import splines
#' @export
#' 
#' @returns 
#' \describe{
#'  List of containing the following:
#'  \item{\code{effect_inf_no_abx}}{numeric effect of infection on growth in subgroup that did *not* receive antibiotics}
#'  \item{\code{effect_inf_abx}}{numeric effect of infection on growth in subgroup that received antibiotics}
#'  \item{\code{abx_0_inf_1}}{expected growth outcome in infected subgroup who did not receive abx}
#'  \item{\code{abx_0_inf_0}}{expected growth outcome in uninfected subgroup who did not receive abx}
#'  \item{\code{abx_1_inf_1}}{expected growth outcome in infected subgroup who received abx}
#'  \item{\code{abx_1_inf_0}}{expected growth outcome in uninfected subgroup who receieved abx}
#'  }
abx_growth_gcomp <- function(data, 
                             laz_var_name = "mo3_haz",
                             abx_var_name = "who_rec_abx",
                             infection_var_name = "tac_shigella_attributable",
                             severity_list = c(
                               "enroll_diar_blood",
                               "enroll_diar_vom_days",
                               "enroll_diar_fever_days",
                               "enroll_diar_vom_num"
                             ),
                             covariate_list = c(
                               "sex",
                               "enr_age_months",
                               "enr_haz",
                               "final_quintile",
                               "enroll_site"
                             ),
                             site_var_name = "enroll_site",
                             site_interaction = TRUE,
                             age_var_name = "enr_age_months"){
  
  # if age in covariate_list, change to spline with 3 knots to increase flexibility
  if(age_var_name %in% covariate_list){
    covariate_list <- covariate_list[covariate_list != age_var_name]
    covariate_list <- c(covariate_list, paste0("splines::ns(", age_var_name, ", df = 4)"))
  }
  
  if(!is.null(severity_list)){
    
    # -----------------------------------
    # Longitudinal G-Computation 
    # -----------------------------------
    
    # Get model formula 
    if(site_interaction == "TRUE"){
      
      # if site in covariate list, remove for model1 (only want interaction terms)
      if(length(site_var_name) == 1){
        if(site_var_name %in% covariate_list){
          covariate_list <- covariate_list[covariate_list != site_var_name]
        }
      } else if (any(site_var_name %in% covariate_list)){
        covariate_list <- covariate_list[!covariate_list %in% site_var_name]
      }
      
      model_1_formula <- stats::as.formula(paste(laz_var_name, "~", 
                                          abx_var_name, "+", infection_var_name, "+", 
                                          paste(covariate_list, collapse = "+"), "+",
                                          paste(severity_list, collapse = "+"), "+",
                                          paste(site_var_name, "*", abx_var_name, collapse = "+"), "+",
                                          paste0(infection_var_name, "*", abx_var_name)))
      
      # put site back in covariate list
      if(!is.null(site_var_name)){
        covariate_list <- c(covariate_list, site_var_name)
      }
      
    } else {
      
      # if site was listed but is not already in covariate list, add
      if(!is.null(site_var_name) & (!(site_var_name %in% covariate_list))){
        covariate_list <- c(covariate_list, site_var_name)
      }
      
      model_1_formula <- stats::as.formula(paste(laz_var_name, "~", 
                                          abx_var_name, "+", infection_var_name, "+", 
                                          paste(covariate_list, collapse = "+"), "+",
                                          paste(severity_list, collapse = "+"), "+",
                                          paste0(infection_var_name, "*", abx_var_name)))
    }
    
    # Step 1: regress LAZ on abx, infection, all severity / non-mediating variables
    model_1 <- stats::glm(model_1_formula,
                   data = data, 
                   family = "gaussian")
    
    # Step 2: predict from model setting abx = 0, infection = 1
    data_01 <- data
    data_01[[infection_var_name]] <- 1
    data_01[[abx_var_name]] <- 0
    
    # predict from the subset model (that no longer includes abx or infection)
    yhat_01 <- stats::predict(model_1, newdata = data_01)
    
    # Step 3: regress yhat_01 on all other non-mediating variables in subset with infection = 1, call this model2
    data$yhat_01 <- yhat_01
    sub_inf_1 <- data[data[[infection_var_name]] == 1,]
    
    model2 <- stats::glm(stats::as.formula(paste("yhat_01", "~", paste(covariate_list, collapse = "+"))),
                  data = sub_inf_1,
                  family = "gaussian")
    
    # Step 4: predict from model2 on everyone, average predictions, call that single number (the avg) ybar_01
    ybar_01 <- mean(stats::predict(model2, newdata = data), na.rm = TRUE)
    
    # Step 5: predict from model1 setting infection = 0 and abx = 0, call that yhat_00
    data_00 <- data
    data_00[[infection_var_name]] <- 0
    data_00[[abx_var_name]] <- 0
    
    yhat_00 <- stats::predict(model_1, newdata = data_00)
    
    # Step 6: regress yhat_00 on all other non-mediating variables in subset with infection = 0, call this model3
    data$yhat_00 <- yhat_00
    sub_inf_0 <- data[data[[infection_var_name]] == 0,]
    
    model3 <- stats::glm(stats::as.formula(paste("yhat_00", "~", paste(covariate_list, collapse = "+"))),
                  data = sub_inf_0,
                  family = "gaussian")
    
    # Step 7: stats::predict from model3 on everyone, average stats::predictions, call that number ybar_00
    ybar_00 <- mean(stats::predict(model3, newdata = data), na.rm = TRUE)
    
    # Step 8: effect of infection without abx = ybar_01 - ybar_00
    inf_no_abx <- ybar_01 - ybar_00
    
    # Step 9: stats::predict from model1 setting infection = 1 and abx = 1, call that yhat_11
    data_11 <- data
    data_11[[infection_var_name]] <- 1
    data_11[[abx_var_name]] <- 1
    
    yhat_11 <- stats::predict(model_1, newdata = data_11)
    
    # Step 10: regress yhat_11 on all other non-mediating variables in subset with infection = 1, call this model4
    data$yhat_11 <- yhat_11
    sub_inf_1 <- data[data[[infection_var_name]] == 1,]
    
    model4 <- stats::glm(stats::as.formula(paste("yhat_11", "~", paste(covariate_list, collapse = "+"))),
                  data = sub_inf_1,
                  family = "gaussian")
    
    # Step 11: stats::predict from model4 on everyone, average stats::predictions, call avg ybar_11
    ybar_11 <- mean(stats::predict(model4, newdata = data), na.rm = TRUE)
    
    # Step 12: stats::predict from model1 setting infection = 0 and abx = 1, call that yhat_10
    data_10 <- data
    
    data_10[[infection_var_name]] <- 0
    data_10[[abx_var_name]] <- 1 
    
    yhat_10 <- stats::predict(model_1, newdata = data_10)
    
    # Step 13: regress yhat_10 on all other blah blah in subset with infection = 0, call this model5
    data$yhat_10 <- yhat_10
    sub_inf_0 <- data[data[[infection_var_name]] == 0,]
    
    model5 <- stats::glm(stats::as.formula(paste("yhat_10", "~", paste(covariate_list, collapse = "+"))),
                  data = sub_inf_0,
                  family = "gaussian")
    
    # Step 14: stats::predict from model5 on everyone, average stats::predictions, call that avg ybar_10
    ybar_10 <- mean(stats::predict(model5, newdata = data), na.rm = TRUE)
    
    # Step 15: effect of infection with abx = ybar_11 - ybar_10
    inf_abx <- ybar_11 - ybar_10
    
    # RETURN RESULTS
    return(list(effect_inf_no_abx = inf_no_abx,
                effect_inf_abx = inf_abx,
                abx_0_inf_1 = ybar_01,
                abx_0_inf_0 = ybar_00,
                abx_1_inf_1 = ybar_11,
                abx_1_inf_0 = ybar_10))
  } else {
    
    # ----------------------------------------
    # Traditional G-Computation 
    # ----------------------------------------
    if(site_interaction == "TRUE"){
      model_1_formula <- stats::as.formula(paste(laz_var_name, "~",
                                          abx_var_name, "+", infection_var_name, "+",
                                          paste(covariate_list, collapse = "+"), "+",
                                          paste0(site_var_name, "*", abx_var_name), "+",
                                          paste0(infection_var_name, "*", abx_var_name)))
    } else {
      model_1_formula <- stats::as.formula(paste(laz_var_name, "~",
                                          abx_var_name, "+", infection_var_name, "+",
                                          paste(covariate_list, collapse = "+"), "+",
                                          paste0(infection_var_name, "*", abx_var_name)))
    }
    
    # Fit model with LAZ ~ infection + abx + covariates + infection*abx
    model_1 <- stats::glm(model_1_formula,
                   data = data,
                   family = "gaussian")
    
    # Predict Abx 0, infection 1
    data_01 <- data
    data_01[[infection_var_name]] <- 1
    data_01[[abx_var_name]] <- 0
    
    ybar_01 <- mean(stats::predict(model_1, newdata = data_01), na.rm = TRUE)
    
    # Predict Abx 0, infection 0
    data_00 <- data
    data_00[[infection_var_name]] <- 0
    data_00[[abx_var_name]] <- 0
    
    ybar_00 <- mean(stats::predict(model_1, newdata = data_00), na.rm = TRUE)
    
    # Difference
    inf_no_abx <- ybar_01 - ybar_00
    
    # Predict Abx 1, infection 1
    data_11 <- data
    data_11[[infection_var_name]] <- 1
    data_11[[abx_var_name]] <- 1
    
    ybar_11 <- mean(stats::predict(model_1, newdata = data_11), na.rm = TRUE)
    
    # Predict Abx 1, infection 0
    data_10 <- data
    data_10[[infection_var_name]] <- 0
    data_10[[abx_var_name]] <- 1
    
    ybar_10 <- mean(stats::predict(model_1, newdata = data_10), na.rm = TRUE)
    
    # Difference
    inf_abx <- ybar_11 - ybar_10
    
    # return list with results
    return(list(effect_inf_no_abx = inf_no_abx,
                effect_inf_abx = inf_abx, 
                abx_0_inf_1 = ybar_01,
                abx_0_inf_0 = ybar_00,
                abx_1_inf_1 = ybar_11,
                abx_1_inf_0 = ybar_10))
  }
  
}
