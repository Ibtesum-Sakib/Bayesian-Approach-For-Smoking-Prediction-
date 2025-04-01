library(tidyverse)
library(tidyr)
library(brms)
library(loo)
library("rstan")
library("gridExtra")
library("grid")



# Load the Data________________________________________________________________
data <- read.csv("smoking.csv")


# Drop unnecessary columns____________________________________________________
data <- data %>%
  select(-X, -amt_weekends, -amt_weekdays, -type)

# Data preprocessing______________________________________
data <- data %>%
  filter(
    !nationality %in% c("Refused", "Unknown"),
    !ethnicity %in% c("Refused", "Unknown"),
    !gross_income %in% c("Refused", "Unknown")
  ) %>%
  mutate(
    nationality = droplevels(factor(nationality)),
    ethnicity = droplevels(factor(ethnicity)),
    gross_income = droplevels(factor(gross_income)),
    region = droplevels(factor(region)),
    gender = factor(gender),
    marital_status = factor(marital_status),
    highest_qualification = factor(highest_qualification),
    smoke = factor(ifelse(smoke == "Yes", 1, 0))  
  )
# Visualize data_______________________________________________________________
data$gincome <- data$gross_income
data <- data %>%
  mutate(
    gincome = as.numeric(gsub("[^0-9]", "", gincome)),  
    income_group = case_when(
      gincome <= 20000 ~ "Low",
      gincome > 20000 & gincome <= 50000 ~ "Medium",
      gincome > 50000 ~ "High",
      TRUE ~ NA_character_  
    )
  )

smoking_rate_by_income <- data %>%
  filter(!is.na(income_group)) %>%  
  group_by(income_group) %>%
  summarise(
    smoke_rate = mean(smoke == 1, na.rm = TRUE),  
    n = n()
  )

print(smoking_rate_by_income)

ggplot(smoking_rate_by_income, aes(x = income_group, y = smoke_rate, fill = income_group)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = c("Low" = "red", "Medium" = "orange", "High" = "green")) +  # Custom colors
  labs(
    title = "Smoking Rate by Income Group",
    x = "Income Group",
    y = "Proportion of Smokers"
  ) +
  theme_minimal()

data <- data %>%
  mutate(
    age = age,
    age_group = case_when(
      age >= 18 & age <= 30 ~ "18-30",
      age > 30 & age <= 45 ~ "31-45",
      age > 45 & age <= 60 ~ "46-60",
      age > 60 ~ "60+",
      TRUE ~ "Unknown"  
    )
  )
summary(data$age)

smoking_rate_by_age <- data %>%
  group_by(age_group) %>%
  summarise(
    smoke_rate = mean(smoke == "1", na.rm = TRUE),  
    n = n()  
  )


print(smoking_rate_by_age)


ggplot(smoking_rate_by_age, aes(x = age_group, y = smoke_rate)) +
  geom_bar(stat = "identity", fill = "lightgreen") +
  labs(
    title = "Smoking Rate by Age Group",
    x = "Age Group",
    y = "Proportion of Smokers"
  ) +
  theme_minimal()



# Model fitting________________________________________________________________
model1 <- brm(
  formula = smoke ~ age + gender + gross_income + marital_status + highest_qualification +
    nationality + ethnicity + (1 | region),#varying intercept for region
  data = data,
  family = bernoulli(),  # Binary outcome (smoke: 0 or 1)
  prior = c(            # specified priors
    prior(normal(0, 0.5), class = "b"), 
    prior(normal(0, 0.02), class = "b", coef = "age"), 
    prior(student_t(3, 0, 5), class = "Intercept"),  
    prior(student_t(3, 0, 2.5), class = "sd")  
  ),
  chains = 4,  # Number of MCMC chains
  iter = 2000,  # Total iterations per chain
  warmup = 1000,  # Warmup iterations
  cores = 4,  # Number of CPU cores to use
  seed = 123  # Set seed for reproducibility
)

model2 <- brm(
  formula = smoke ~ age + gender + gross_income + marital_status + nationality+
    ethnicity +highest_qualification + (0 + highest_qualification|region),  #varying slopes for highest qualification by region
  data = data,
  family = bernoulli(),
  prior = c(
    prior(normal(0, 0.5), class = "b"),  
    prior(normal(0, 0.02), class = "b", coef = "age"),  
    prior(student_t(3, 0, 5), class = "Intercept"), 
    prior(student_t(3, 0, 2.5), class = "sd", group = "region")  
  ),
  chains = 4,
  iter = 2000,
  warmup = 1000,
  cores = 4,
  seed = 123  # Set seed for reproducibility
  )

model3 <- brm(
  formula = smoke ~ age + gender + marital_status + highest_qualification +
    nationality + ethnicity + gross_income + (1 + highest_qualification | region),# Both varying intercepts and slopes for highest qualification by region
  data = data,
  family = bernoulli(),
  prior = c(
    prior(normal(0, 0.5), class = "b"),  
    prior(normal(0, 0.02), class = "b", coef = "age"),  
    prior(student_t(3, 0, 5), class = "Intercept"),  
    prior(student_t(3, 0, 2.5), class = "sd", group = "region"),
    prior(lkj(2), class = "cor")
  ),
  chains = 4,
  iter = 2000,
  warmup = 1000,
  cores = 4,
  seed = 123  # Set seed for reproducibility
  
)

 


# Summarize the results of the Bayesian model__________________________________________
summary(model1)
summary(model2)
summary(model3)

# Plot the posterior distributions_______________________________________________________
  plot(model1)
  plot(model2)
  plot(model3)
  

#Convergence diagnostic_________________________________________________________________
s1 <- model1$fit
s2 <- model2$fit
s3 <- model3$fit

t1 <-traceplot(s1)
t2 <-traceplot(s2)
t3 <-traceplot(s3)

#posterior predictive check_____________________________________________________________
p1 <- pp_check(model1)
p2 <- pp_check(model2)
p3 <- pp_check(model3)
grid.arrange(p1,p2,p3,textGrob("model1"), textGrob("model2"), textGrob("model3"), ncol = 3, heights = c(5, 0.1))

#Leave-one-out cross validation_________________________________________________________
l3 <- loo(model3)
l2 <- loo(model2)
l1 <- loo(model1)


loo_compare(l2,l1,l3)
