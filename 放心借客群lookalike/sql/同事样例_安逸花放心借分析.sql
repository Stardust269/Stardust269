-- ******************************************************************** --
-- author: yanyan.zheng@msxf.com
-- create time: 2026-07-23 09:51:00
-- 归档：放心借客群 lookalike 项目（探索 SQL，非生产一键脚本）
-- ******************************************************************** --
select count(1) as num, sum(if(if_ayh_types ='安逸花重叠客户',1,0)) as num_1
from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
limit 10;
----
select *
from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
limit 10;

--- 放心借特征变量 
select *
from lj_iceberg.lods_extds.open_tt_credit
where dt = '20260722'
limit 10;

-- 腾讯
select *
from lj_iceberg.lods_extds.extds_tx_cpd_fpd_lable2026_response
where dt = '20260722'
limit 10;

--  百行
select *
from lj_iceberg.lods_extds.bh_rzdz_v2_result
where dt = '20260722'
limit 10;

--  朴道
select *
from lj_iceberg.lods_extds.extds_pd_multiloans_v31_result
where dt = '20260722'
limit 10;

-- 看下交集人群的情况 --
-- 2026-02-10	2026-06-29 -- 
select min(lend_date_sj) as lend_date_sj_min
, max(lend_date_sj) as lend_date_sj_max
from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
 -- where if_ayh_types = '安逸花重叠客户'
;
-- 1668024
SELECT  count(1),count(DISTINCT unique_id)
from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
;

-- 2026-02-10	2026-06-29 -- 
-- 看看前后余额的变化
-- 看看前后人群属性的变化
-- 看看活跃度等特征
select case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end as y_loan_base_rate_flg
  , count(1) as num
  , avg(org_credit_lim_yx) AS org_credit_lim_yx
  , avg(crdt_lim_yx_ayh) as crdt_lim_yx_ayh
  , avg(lend_amt) as lend_amt
  from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
  where if_ayh_types = '安逸花重叠客户'
  group by case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end ;

drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_01;
create table if not exists lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_01 as 
select unique_id,lend_date_sj
,y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  , avg(if(days_dt < lend_date_sj, coalesce(pril_bal,0), null)) as pril_bal_avg_before 
  , avg(if(days_dt > lend_date_sj, coalesce(pril_bal,0), null)) as pril_bal_avg_after 
  , max(if(date_add(days_dt,1) = lend_date_sj, if_lend, null)) as if_lend_before
  , max(if(date_sub(days_dt,1) = lend_date_sj, if_lend, null)) as if_lend_after 
  , max(if(date_add(days_dt,1) = lend_date_sj, cust_types_01, null)) as cust_types_01_before
  , max(if(date_sub(days_dt,1) = lend_date_sj, cust_types_01, null)) as cust_types_01_after 
from (
  select unique_id,lend_date_sj
  , case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end as y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
  where if_ayh_types = '安逸花重叠客户'
)t1 
left join (
  select uuid,user_id,if_lend,cust_types_01,pril_bal,concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2))  as days_dt
  from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
  where dt >='20260201' and dt <= '20260707' AND sx_rowid=1 and prod_cd='5103'
)t2 
on t1.unique_id = t2.uuid
and days_dt BETWEEN date_sub(lend_date_sj,7) and date_add(lend_date_sj,7)
group by unique_id,lend_date_sj
,y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
;

select *
from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_01 
limit 10;

select y_loan_base_rate_flg
, count(1) as num
, sum(if(lend_amt>0,1,0)) as fxj_yye_num
, avg(lend_amt) as lend_amt
, sum(pril_bal_avg_before)/count(1) as pril_bal_avg_before
, sum(pril_bal_avg_after)/count(1) as pril_bal_avg_after
, sum(if(pril_bal_avg_before >0,1,0)) as yye_before_num
, sum(if(pril_bal_avg_after >0,1,0)) as yye_after_num
, sum(pril_bal_avg_before)/sum(if(pril_bal_avg_before >0,1,0)) as pril_bal_avg_before_1
, sum(pril_bal_avg_after)/sum(if(pril_bal_avg_after >0,1,0)) as pril_bal_avg_after_1
from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_01 
group by y_loan_base_rate_flg
;

select y_loan_base_rate_flg
,if_lend_before,cust_types_01_before
, count(1) as num
, avg(lend_amt) as lend_amt
, sum(pril_bal_avg_before)/count(1) as pril_bal_avg_before
, sum(pril_bal_avg_after)/count(1) as pril_bal_avg_after
, sum(if(pril_bal_avg_before >0,1,0)) as yye_before_num
, sum(if(pril_bal_avg_after >0,1,0)) as yye_after_num
, sum(pril_bal_avg_before)/sum(if(pril_bal_avg_before >0,1,0)) as pril_bal_avg_before_1
, sum(pril_bal_avg_after)/sum(if(pril_bal_avg_after >0,1,0)) as pril_bal_avg_after_1
from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_01 
group by y_loan_base_rate_flg,if_lend_before,cust_types_01_before
;

drop table lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_02;
create table if not exists lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_02 as 
select t1.unique_id,lend_date_sj
,y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  , max(if(days_dt < lend_date_sj, 1, 0)) as is_login_before
  , max(if(days_dt > lend_date_sj, 1, 0)) as is_login_after 
from (
  select unique_id,lend_date_sj
  , case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end as y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
  where if_ayh_types = '安逸花重叠客户'
)t1
left join (
  select unique_id,user_id 
  from lj_iceberg.dwd.dwd_ip_cust_info_df
  where dt='20260723' 
  group by unique_id,user_id 
) t2 
on t1.unique_id = t2.unique_id
left join (
  SELECT user_id,dt,event_time, date_format(TO_DATE(dt, 'yyyyMMdd'), 'yyyy-MM-dd') as days_dt
  FROM dwd.dwd_ma_flow_server_di
  where dt >='20260201' and dt <= '20260707' AND is_login_id_p = 1 AND event_name = 'api_event_login'
)t3 
on t2.user_id = t3.user_id
and days_dt BETWEEN date_sub(lend_date_sj,7) and date_add(lend_date_sj,7)
group by t1.unique_id,lend_date_sj
,y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
;

select count(1) 
from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_02
limit 10;

select y_loan_base_rate_flg
,is_login_after
, count(1) as num
from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0724_02
group by y_loan_base_rate_flg,is_login_after
;

--- 种子用户数量 ---
select case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end as y_loan_base_rate_flg
  , count(1) as num
  , avg(org_credit_lim_yx) AS org_credit_lim_yx
  , avg(crdt_lim_yx_ayh) as crdt_lim_yx_ayh
  , avg(lend_amt) as lend_amt
  from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
  group by case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end ;

--- 背景人群处理 ---
select min(standard_score ) as standard_score_min ,  max(standard_score ) as standard_score_max
from  lj_iceberg.model_deployment.m1_mgt_master_score_model_13_1  
where dt = '20260720'
limit 10;

drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0728_01;
create table if not exists  lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0728_01 as 
SELECT t1.uuid,user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,block_type
    , days_dt_zx ,dt_zx, ms_model_score
  from (
    SELECT tt1.uuid,user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,block_type
    , days_dt_zx ,dt_zx
    ,row_number() OVER (PARTITION by tt1.uuid order by days_dt_zx desc) as rnk
    from 
    (select uuid,user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,block_type
    from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
    where dt ='20260630' AND sx_rowid=1 and prod_cd='5103'
    group by uuid,user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,block_type
    )tt1 
    left join (
    select id_unqp, dt as dt_zx, concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary 
    where dt>='20260210' and dt <'20260629' 
    group by id_unqp, dt 
    )tt2 
    on tt1.uuid = tt2.id_unqp
  )t1
  left join (
    select union_id,standard_score ms_model_score ,date_add(from_unixtime(unix_timestamp(dt,'yyyymmdd'),'yyyy-mm-dd'),1) ms_days_dt  
    from  lj_iceberg.model_deployment.m1_mgt_master_score_model_13_1  
where dt>='20260209' and dt <'20260628'
  ) t2 
  on t1.uuid = t2.union_id and t1.days_dt_zx = t2.ms_days_dt
  where rnk = 1
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0729_01;
create table if not exists  lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0729_01 as 
SELECT t1.uuid,t1.user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,block_type
    , days_dt_zx ,dt_zx, ms_model_score
from (
  select uuid,user_id, days_dt_zx ,dt_zx, ms_model_score
  from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0728_01
)t1 
left join (
  select uuid,user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,block_type
  , date_add(from_unixtime(unix_timestamp(dt,'yyyymmdd'),'yyyy-mm-dd'),1) as ayh_days_dt
    from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
    where dt>='20260209' and dt <'20260628' AND sx_rowid=1 and prod_cd='5103'
)t2 
on t1.days_dt_zx = t2.ayh_days_dt and t1.uuid = t2.uuid and t1.user_id = t2.user_id
;

select count(1) as num
,count(DISTINCT  uuid) as usr_num
,sum(if(ms_model_score >= 630,1,0)) as xz_num 
,sum(if(ms_model_score >= 670,1,0)) as xz_num_1 
,sum(if(ms_model_score >= 720,1,0)) as xz_num_1 
from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0729_01
where block_type not in ('过期','销户')
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0728_02;
create table if not exists  lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0728_02 as 
select unique_id,lend_date_sj,y_loan_base_rate_flg
, org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  ,if_ayh_types
  ,ms_model_score
  , avail_cash_credit_lmt_5103
  , duot_cnt
from (
  select unique_id,lend_date_sj
  , case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end as y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  , if_ayh_types
  from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
)t1
left join
( SELECT union_id,standard_score ms_model_score 
     ,date_add(from_unixtime(unix_timestamp(dt,'yyyymmdd'),'yyyy-mm-dd'),1) ms_days_dt
    from lj_iceberg.model_deployment.m1_mgt_master_score_model_13_1
    where dt>='20260209' and dt<='20260628'
) t2 
on t1.unique_id = t2.union_id and t1.lend_date_sj = t2.ms_days_dt
left join
( select uuid,user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,date_add(from_unixtime(unix_timestamp(dt,'yyyymmdd'),'yyyy-mm-dd'),1) ms_days_dt 
  from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
  where dt>='20260209' and dt<='20260628' AND sx_rowid=1 and prod_cd='5103'
  group by uuid,user_id,if_lend,cust_types_01,pril_bal,avail_cash_credit_lmt_5103,duot_cnt,dt
) t3 
on t1.unique_id = t3.uuid and t1.lend_date_sj = t3.ms_days_dt;

--- 种子用户征信报告关联（首借日前后窗口 + 取最近一份）---
drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0729_02;
create table if not exists  lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0729_02 as 
select unique_id,lend_date_sj,y_loan_base_rate_flg
, org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  ,if_ayh_types
  ,days_dt_zx
  ,dt_zx
  , row_number() over (PARTITION BY unique_id,lend_date_sj,y_loan_base_rate_flg
, org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  ,if_ayh_types ORDER BY days_dt_zx desc) as rnk
from (
  select unique_id,lend_date_sj
  , case when y_loan_base_rate < 0.15 then 1 
    when y_loan_base_rate < 0.18 then 2
    when y_loan_base_rate = 0.18 then 3
    when y_loan_base_rate <= 0.2 then 4
    else 5 end as y_loan_base_rate_flg
  , org_credit_lim_yx
  , crdt_lim_yx_ayh
  , lend_amt
  , if_ayh_types
  from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630 
)t1
left join (
  select id_unqp, dt as dt_zx, concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt_zx
  , date_add(concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)),3) as days_dt_zx_3
  from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary 
  where dt>='20260210' and dt <'20260629' 
  group by id_unqp, dt 
)t2 
on t1.unique_id = t2.id_unqp and days_dt_zx <= lend_date_sj and days_dt_zx_3 >= lend_date_sj
;

select y_loan_base_rate_flg,count(1) as num ,count(distinct unique_id), sum(if(days_dt_zx is not null,1,0)) as days_dt_zx_num 
, sum(if(days_dt_zx = lend_date_sj,1,0)) as days_dt_zx_num_1 
from lj_iceberg.ai_decision_dev.fxj_ayh_usr_analyse_0729_02 
WHERE rnk =1
GROUP BY y_loan_base_rate_flg
;

-- 注：原稿中含「多头」长 SQL 与 duot_cnt 下线说明，扩量样本加工见 fxj_seed_users_attach_credit_feature.sql
