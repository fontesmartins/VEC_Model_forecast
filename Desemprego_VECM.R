########################## Desemprego - VEC Model ######################



library(sidrar)
library(readxl)
library(forecast)
library(tidyverse)
library(lubridate)
library(rbcb)
library(tstools)
library(Quandl)
library(forecast)
library(scales)
library(gridExtra)
library(caret)
library(vars)

## Coleta e tratamento dos dados 

##  FBCF PNAD/IBGE
url = 'https://www.ipea.gov.br/cartadeconjuntura/wp-content/uploads/2022/03/220404_cc_53_dados_indicador_ipea_fbcf_dez21.xlsx'
download.file(url, destfile = 'fbcf.xlsx', mode = 'wb')
fbcf_raw <- read_excel('fbcf.xlsx', col_names = T, skip = 1)



fbcf <- fbcf_raw[,5] %>% 
  rename('FBCF' = `Indicador Ipea de FBCF` ) %>% 
  ts(start = c(1996,01),end = c(2019,12), frequency = 12) %>% 
  window(start = c(2012,04))




## IPCA - S�rie hist�rica com n�mero �ndice - Dados do IBGE
ipca <- get_sidra(api='/t/1737/n1/all/v/2266/p/all/d/v2266%2013') %>%
  pull(Valor) %>%
  ts(start=c(1979,12), end = c(2019,12), freq=12) %>%
  window(start=c(2012,04) ) 



## SELIC dados do Banco central
selic <- GetBCBData::gbcbd_get_series(id= 4189,
                                      first.date = '2012-04-01',
                                      last.date = '2019-12-01',
                                      use.memoise = F)  %>% 
  pull(value) %>%
  ts(start = c(2012,04), frequency = 12) 


## Dados PNAD 
pnad.raw = get_sidra(api='/t/6318/n1/all/v/1641/p/all/c629/all')

desocupada <- pnad.raw %>%
  filter(`Condi��o em rela��o � for�a de trabalho e condi��o de ocupa��o (C�digo)` == 32446) %>%
  .[-length(pnad.raw),] %>%
  pull(Valor) %>% 
  ts(start=c(2012,03),end = c(2019,12), freq=12)  

forca_de_trabalho <- pnad.raw %>%
  filter(`Condi��o em rela��o � for�a de trabalho e condi��o de ocupa��o (C�digo)` == 32386) %>%
  .[-length(pnad.raw),] %>%
  pull(Valor) %>% 
  ts(start=c(2012,03),end = c(2019,12), freq=12)

desemprego <- desocupada/forca_de_trabalho*100
desemprego = ts(desemprego[-1],start = c(2012,04), frequency = 12)





## Juntando as s�ries temporais
data_ts <- ts.intersect(desemprego, fbcf, selic, ipca) 

df = as.data.frame(data_ts) %>%
  mutate(date = seq(as_date('2012-04-01'), as_date('2019-12-01'), 'month')) %>%
  relocate(date) 



v1 = df  %>% 
  ggplot(aes(x = date)) + 
  geom_line(aes(y =desemprego), size = .9, colour = 'darkblue') + 
  theme(axis.text.x = element_text(angle = 45, hjust = 1), 
        plot.title = element_text(size = 18)) + 
  scale_x_date(breaks = date_breaks('1 year'),
               labels = date_format('%Y')) +
  labs(x = '', y = '% Ocupada',
       title = 'Desemprego - PNAD')


v2 = df  %>% 
  ggplot(aes(x = date)) + 
  geom_line(aes(y =fbcf), size = .9, colour = 'darkblue') + 
  theme(axis.text.x = element_text(angle = 45, hjust = 1), 
        plot.title = element_text(size = 18)) + 
  scale_x_date(breaks = date_breaks('1 year'),
               labels = date_format('%Y')) +
  labs(x = '', y = ' % 1995 = 100',
       title = 'Forma��o Bruta de Capital Fixo')

v3 = df  %>% 
  ggplot(aes(x = date)) + 
  geom_line(aes(y = selic), size = .9, colour = 'darkblue') + 
  theme(axis.text.x = element_text(angle = 45, hjust = 1), 
        plot.title = element_text(size = 18)) + 
  scale_x_date(breaks = date_breaks('1 year'),
               labels = date_format('%Y')) +
  labs(x = '', y = '%',
       title = 'Taxa SELIC') 


v4 = df  %>% 
  ggplot(aes(x = date)) + 
  geom_line(aes(y = ipca), size = .9, colour = 'darkblue') + 
  theme(axis.text.x = element_text(angle = 45, hjust = 1), 
        plot.title = element_text(size = 18)) + 
  scale_x_date(breaks = date_breaks('1 year'),
               labels = date_format('%Y')) +
  labs(x = '', y = '% 1993 = 100 ',
       title = 'Produto Interno Bruto',
       subtitle = 'Valores deflacionados')
grid.arrange(v1,v2,v3,v4,
             layout_matrix = matrix(c(1,2,3,4),
                                    ncol = 2, byrow = T))




## Amostra de treino e teste
df = as.data.frame(data_ts) %>%
  mutate(date = seq(as_date('2012-04-01'), as_date('2019-12-01'), 'month'))
df$date <-  NULL
training.2 = slice(df, -c(82:93))
testing.2 = slice(df, c(82:93))


## Testando cointegra��o 
d <- VARselect(training.2, lag.max = 12, type = 'both')
d$selection


j.eigen <- ca.jo(training.2, type = 'eigen', K = 4,
                 ecdet = 'const',
                 spec = 'transitory',
                 season = 12)
summary(j.eigen)


## Criando modelo VEC
vec = cajorls(j.eigen, r = 3)
summary(vec$rlm)
vec
model.1 = vec2var(j.eigen, r = 3)


# Arch Effects 
arch = arch.test(model.1, lags.multi = 12, multivariate.only = T)
arch

# Normalidade dos res�duos 
norm = normality.test(model.1)
norm
hist(model.1$resid)
## forecast 
forecast <-  predict(model.1, n.ahead = nrow(testing.2), ci = 0.95)
training <- ts(training.2, start = c(2012,04), freq= 12)
testing <- ts(testing.2, start = c(2019,1), frequency = 12)

f.cast_desemprego <- ts(forecast$fcst$desemprego, start = start(testing),
                        frequency = 12)
autoplot(cbind(f.cast_desemprego, testing[,1]))


## Avalia��o
acc = accuracy(f.cast_desemprego, testing[,1])
print(xtable::xtable(acc))
acc
xtable::xtable(acc)
## Visualizando 
df.2 = as.data.frame(forecast$fcst$desemprego) %>%
  mutate(date = seq(as_date('2019-01-01'), as_date('2019-12-01'), 'month')) %>%
  relocate(date) %>%
  rename(fitted=fcst)

df.2$testing = testing.2$desemprego



df.2 %>% 
  ggplot(aes(x = date)) + 
  geom_line(aes(y = fitted, colour = 'Forecast'), size = 1.2) + 
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = .2, fill = 'grey') +
  geom_line(aes(y = testing, colour = 'Testing'), size = 1.2) +
  theme(legend.position = c(.1,.2),
        plot.title = element_text(size = 18)) +
  scale_x_date(breaks = date_breaks('1 month'),
               labels = date_format('%m/%Y')) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) + 
  labs(x = '', y = '%',
       title = 'Brazil Unemployment Rate Forecast',
       subtitle = 'A Vector Error Correction Forecasting Model')




