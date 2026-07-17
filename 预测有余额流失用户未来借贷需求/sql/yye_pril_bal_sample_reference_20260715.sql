-- ******************************************************************** --
-- 同事参考 SQL：三月样本 + 马消特征（20260715）
-- author: yanyan.zheng@msxf.com
-- create time: 2026-07-17 10:15:27
-- 说明：本文件为同事提供的原始示例，用于对照 jcr 三月样本链路
-- 对照说明见：notion_schema/项目说明_三月样本20260715.md
-- 我方征信特征扩展见：sql/run_all_20260715.sql（勿改 run_all_20260623.sql）
-- ******************************************************************** --
----
--分区表里的数据是延后一天的
--dt 20251101存的是 20251031的状态数据  lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df  T-2
-- -- lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df dt就是dt的状态  T-1
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715;
create table if not exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715 as
select uuid,user_id,pril_bal,crdt_lim_yx,pril_bal/crdt_lim_yx as pril_bal_rate  -- 额度利用率用这个
,dt
,concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2))  as days_dt
,substr(dt,1,6) as m
, row_number() over (partition by uuid,user_id,substr(dt,1,6) order by pril_bal/crdt_lim_yx ) as rk
from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
where dt >='20250801' and dt <= '20251031' AND sx_rowid=1 and prod_cd='5103'
and if_lend = '复贷' and cust_types_01 ='有余额' and crdt_lim_yx > 0
;

--加工后续是否变为无余额
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_1;
create table if not exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_1 as
select t1.uuid,t1.user_id,pril_bal,crdt_lim_yx,pril_bal_rate,t1.dt,t1.days_dt,t1.m
, max(no_balance_flg) as no_balance_flg_90
,max(if(t2.days_dt BETWEEN  t1.days_dt and date_add(t1.days_dt,30) ,no_balance_flg ,0)) as no_balance_flg_30
,max(if(t2.days_dt BETWEEN  t1.days_dt and date_add(t1.days_dt,60) ,no_balance_flg ,0)) as no_balance_flg_60
from (
  select uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt, days_dt,m
  from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715
  where rk =1
)t1
left join (
  select uuid,user_id,if(if_lend = '复贷' and cust_types_01 ='无余额',1,0) as no_balance_flg,dt, concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt
  from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
  where dt >='20250831' and dt <= '20260201' AND sx_rowid=1 and prod_cd='5103'
)t2
on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt BETWEEN  t1.days_dt and date_add(t1.days_dt,90)
group by  t1.uuid,t1.user_id,pril_bal,crdt_lim_yx,pril_bal_rate,t1.dt,t1.days_dt,t1.m
;

--加工后是否有提现
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2;
create table if not exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2 as
select t1.*
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN days_dt and date_add(days_dt,30) ,1,0))  as with_0_30
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt,31) and date_add(days_dt,60)  ,1,0))  as with_31_60
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt,61) and date_add(days_dt,90)  ,1,0))  as with_61_90
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2)) BETWEEN date_add(days_dt,91) and date_add(days_dt,120)  ,1,0))  as with_91_120
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN days_dt and date_add(days_dt,30) and prod_cd = '5103',1,0))  as with_0_30_5103
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt,31) and date_add(days_dt,60) and prod_cd = '5103' ,1,0))  as with_31_60_5103
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt,61) and date_add(days_dt,90) and prod_cd = '5103' ,1,0))  as with_61_90_5103
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2)) BETWEEN date_add(days_dt,91) and date_add(days_dt,120) and prod_cd = '5103' ,1,0))  as with_91_120_5103
from (
  SELECT uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,m
  from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_1
)t1
left outer join (
  -- 去重 提现表
                SELECT unique_id, user_id, bhv_time, event, aprv_status , day_time, instal_terms, wdraw_apply_amt, final_loan_amt,prod_cd
                FROM dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
                where dt='get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
                  and day_time >='20250801' and day_time < '20260310'
                  and unique_id is not NULL
                  group by unique_id, user_id, bhv_time, event, aprv_status , day_time, instal_terms, wdraw_apply_amt, final_loan_amt,prod_cd
)t3
on t1.uuid = t3.unique_id
group by uuid,t1.user_id,pril_bal,crdt_lim_yx,pril_bal_rate,t1.dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,m
;

select m,count(1), count(DISTINCT uuid) as usr_num,sum(if(with_0_30+with_31_60=0 and  no_balance_flg_60=1,1,0)) as pnum
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2
where crdt_lim_yx >= 20000
group by m;

select *
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2
limit 10;

-- 构建马消特征--
-- lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df dt就是dt的状态 ，加工余额、有效额度和额度使用率特征
drop table if exists lj_iceberg.ai_decision_dev.ayh_feature_pril_bal_crdt_lim_yx;
create table if not exists lj_iceberg.ai_decision_dev.ayh_feature_pril_bal_crdt_lim_yx (
  uuid string,
  user_id string,
  label int,
  pril_bal decimal(25,2),
  crdt_lim_yx decimal(10,2),
  pril_bal_rate DOUBLE ,
  pril_bal_1w decimal(25,2),
  crdt_lim_yx_1w decimal(10,2),
  pril_bal_rate_1w DOUBLE ,
  pril_bal_1m decimal(25,2),
  crdt_lim_yx_1m decimal(10,2),
  pril_bal_rate_1m DOUBLE ,
  pril_bal_3m decimal(25,2),
  crdt_lim_yx_3m decimal(10,2),
  pril_bal_rate_3m DOUBLE ,
  pril_bal_6m decimal(25,2),
  crdt_lim_yx_6m decimal(10,2),
  pril_bal_rate_6m DOUBLE ,
  pril_bal_1y decimal(25,2),
  crdt_lim_yx_1y decimal(10,2),
  pril_bal_rate_1y DOUBLE ,
  dt string,
  days_dt string
)
;

-- 借据维度有逾期金额 和 逾期期数 --
-- lj_iceberg.dws.dws_loan_info_df 这个表--
-- 以label表做左表来做，需求预测是他的子集，可以复用---
INSERT  OVERWRITE  table lj_iceberg.ai_decision_dev.ayh_feature_pril_bal_crdt_lim_yx
select  uuid,user_id,label
,pril_bal
,crdt_lim_yx
,pril_bal_rate
,pril_bal_1w,crdt_lim_yx_1w
,if(crdt_lim_yx_1w >0, pril_bal_1w/crdt_lim_yx_1w, null) as pril_bal_rate_1w
,pril_bal_1m,crdt_lim_yx_1m
,if(crdt_lim_yx_1m >0, pril_bal_1m/crdt_lim_yx_1m, null) as pril_bal_rate_1m
,pril_bal_3m,crdt_lim_yx_3m
,if(crdt_lim_yx_3m >0, pril_bal_3m/crdt_lim_yx_3m, null) as pril_bal_rate_3m
,pril_bal_6m,crdt_lim_yx_6m
,if(crdt_lim_yx_6m >0, pril_bal_6m/crdt_lim_yx_6m, null) as pril_bal_rate_6m
,pril_bal_1y,crdt_lim_yx_1y
,if(crdt_lim_yx_1y >0, pril_bal_1y/crdt_lim_yx_1y, null) as pril_bal_rate_1y
,dt
,days_dt
from (SELECT t1.uuid,t1.user_id,t1.label
,t1.pril_bal
,t1.crdt_lim_yx
,t1.pril_bal_rate
, avg(if(t2.days_dt >= date_sub(t1.days_dt,6), t2.pril_bal, null)) as pril_bal_1w
, avg(if(t2.days_dt >= date_sub(t1.days_dt,6), t2.crdt_lim_yx, null)) as crdt_lim_yx_1w
, avg(if(t2.days_dt >= date_sub(t1.days_dt,29), t2.pril_bal, null)) as pril_bal_1m
, avg(if(t2.days_dt >= date_sub(t1.days_dt,29), t2.crdt_lim_yx, null)) as crdt_lim_yx_1m
, avg(if(t2.days_dt >= date_sub(t1.days_dt,89), t2.pril_bal, null)) as pril_bal_3m
, avg(if(t2.days_dt >= date_sub(t1.days_dt,89), t2.crdt_lim_yx, null)) as crdt_lim_yx_3m
, avg(if(t2.days_dt >= date_sub(t1.days_dt,179), t2.pril_bal, null)) as pril_bal_6m
, avg(if(t2.days_dt >= date_sub(t1.days_dt,179), t2.crdt_lim_yx, null)) as crdt_lim_yx_6m
, avg(t2.pril_bal) as pril_bal_1y
, avg(t2.crdt_lim_yx) as crdt_lim_yx_1y
,t1.dt
,t1.days_dt
from (
  select uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt,days_dt,if(with_0_30+with_31_60=0 and  no_balance_flg_60=1,1,0) as label
  from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2
  where crdt_lim_yx >= 20000
)t1
left join (
  select uuid,user_id,pril_bal,crdt_lim_yx,concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt
  from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
  where dt >= '20240801' and dt <= '20251031'
  and prod_cd = '5103' and crdt_lim_yx>0 AND sx_rowid=1
)t2
on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt BETWEEN  date_sub(t1.days_dt,359) and t1.days_dt
group by t1.uuid,t1.user_id,t1.label
,t1.pril_bal
,t1.crdt_lim_yx
,t1.pril_bal_rate
,t1.dt
,t1.days_dt
)t
;

-- 发起成功次数 --
--dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df   提现表来加工--
-- 因为近1年内可能有未发起的用户，导致这个表用户数会稍微少一点--
-- drop table if exists lj_iceberg.ai_decision_dev.ayh_feature_wdraw_fq_suc;
create table if not exists lj_iceberg.ai_decision_dev.ayh_feature_wdraw_fq_suc (
  uuid string,
  user_id string,
  label int,
  fq_cnt_1w int,
  suc_cnt_1w int,
  pass_rate_1w DOUBLE ,
  fq_cnt_1m int,
  suc_cnt_1m int,
  pass_rate_1m DOUBLE ,
  fq_cnt_3m int,
  suc_cnt_3m int,
  pass_rate_3m DOUBLE ,
  fq_cnt_6m int,
  suc_cnt_6m int,
  pass_rate_6m DOUBLE ,
  fq_cnt_1y int,
  suc_cnt_1y int,
  pass_rate_1y DOUBLE ,
  dt string,
  days_dt string
)
;
insert OVERWRITE  table lj_iceberg.ai_decision_dev.ayh_feature_wdraw_fq_suc
select  uuid,user_id,label
,fq_cnt_1w,suc_cnt_1w
,if(suc_cnt_1w >0, fq_cnt_1w/suc_cnt_1w, null) as pass_rate_1w
,fq_cnt_1m,suc_cnt_1m
,if(suc_cnt_1m >0, fq_cnt_1m/suc_cnt_1m, null) as pass_rate_1m
,fq_cnt_3m,suc_cnt_3m
,if(suc_cnt_3m >0, fq_cnt_3m/suc_cnt_3m, null) as pass_rate_3m
,fq_cnt_6m,suc_cnt_6m
,if(suc_cnt_6m >0, fq_cnt_6m/suc_cnt_6m, null) as pass_rate_6m
,fq_cnt_1y,suc_cnt_1y
,if(suc_cnt_1y >0, fq_cnt_1y/suc_cnt_1y, null) as pass_rate_1y
,dt
,days_dt
from (SELECT t1.uuid,t1.user_id,t1.label
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,6), 1, 0)) as fq_cnt_1w
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,6) and final_loan_amt >0, 1, 0)) as suc_cnt_1w
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,29), 1, 0)) as fq_cnt_1m
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,29) and final_loan_amt >0, 1, 0)) as suc_cnt_1m
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,89), 1, 0)) as fq_cnt_3m
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,89) and final_loan_amt >0, 1, 0)) as suc_cnt_3m
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,179), 1, 0)) as fq_cnt_6m
, sum(if(t2.draw_apply_date >= date_sub(t1.days_dt,179) and final_loan_amt >0, 1, 0)) as suc_cnt_6m
, sum(1) as fq_cnt_1y
, sum(if(final_loan_amt >0 ,1, 0)) as suc_cnt_1y
,t1.dt
,t1.days_dt
from (
  select uuid,user_id,dt,days_dt,if(with_0_30+with_31_60=0 and  no_balance_flg_60=1,1,0) as label
  from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2
  where crdt_lim_yx >= 20000
)t1
left join (
  SELECT unique_id, user_id, wdraw_apply_no,bhv_time, event, aprv_status , day_time, instal_terms, wdraw_apply_amt, final_loan_amt,prod_cd, draw_apply_date
  FROM dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
  where dt='get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
  and day_time >='20240801' and day_time <= '20251031'
  and unique_id is not NULL
  group by unique_id, user_id,wdraw_apply_no, bhv_time, event, aprv_status , day_time, instal_terms, wdraw_apply_amt, final_loan_amt,prod_cd,draw_apply_date

)t2
on t1.uuid = t2.unique_id and t1.user_id = t2.user_id
where t2.draw_apply_date BETWEEN  date_sub(t1.days_dt,359) and t1.days_dt
group by t1.uuid,t1.user_id,t1.label
,t1.dt
,t1.days_dt
)t
;
