-- ******************************************************************** --
-- 同事参考 SQL：有余额未来流失（样本 + 标签统计）
-- author: yanyan.zheng@msxf.com
-- create time: 2026-07-09 15:41:43
-- 说明：本文件为同事提供的原始示例，用于对照 jcr 特征链路中的样本/标签口径
-- 对照说明见：notion_schema/项目说明_同事样本SQL对照.md
-- ******************************************************************** --

--复贷有余额的用户 ，额度利用率
--分区表里的数据是延后一天的
--dt 20251101存的是 20251031的状态数据
-- drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623;
create table if not exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623 as
select uuid,user_id,pril_bal,crdt_lim_yx,pril_bal/crdt_lim_yx as pril_bal_rate    -- 额度利用率用这个
,curt_crdt_line_yx ,pril_bal/curt_crdt_line_yx as pril_bal_rate_1
,crdt_lim_op,pril_bal/crdt_lim_op as pril_bal_rate_2
,dt, row_number() over (partition by uuid,user_id order by pril_bal/crdt_lim_yx ) as rk
, row_number() over (partition by uuid,user_id order by pril_bal/curt_crdt_line_yx ) as rk_1
, row_number() over (partition by uuid,user_id order by pril_bal/crdt_lim_op ) as rk_2
from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
where dt >='20251002' and dt <= '20251101' AND sx_rowid=1 and prod_cd='5103'
and if_lend = '复贷' and cust_types_01 ='有余额' and crdt_lim_yx > 0
;

--复贷有余额的用户 ，取的月内额度利用率最低的那一天做后续流失的判断
--加工后续是否变为无余额
-- drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_1;
create table if not exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_1 as
select t1.uuid,t1.user_id,pril_bal,crdt_lim_yx,pril_bal_rate,t1.dt,t1.days_dt
, max(no_balance_flg) as no_balance_flg_90
,max(if(t2.days_dt BETWEEN  t1.days_dt and date_add(t1.days_dt,30) ,no_balance_flg ,0)) as no_balance_flg_30
,max(if(t2.days_dt BETWEEN  t1.days_dt and date_add(t1.days_dt,60) ,no_balance_flg ,0)) as no_balance_flg_60
from (
  select uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt, concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt
  from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623
  where rk =1
)t1
left join (
  select uuid,user_id,if(if_lend = '复贷' and cust_types_01 ='无余额',1,0) as no_balance_flg,dt, concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt
  from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
  where dt >='20251101' and dt <= '20260201' AND sx_rowid=1 and prod_cd='5103'
)t2
on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt BETWEEN  t1.days_dt and date_add(t1.days_dt,90)
group by  t1.uuid,t1.user_id,pril_bal,crdt_lim_yx,pril_bal_rate,t1.dt,t1.days_dt
;

--加工后续是否有征信，是否有提现
create table if not exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2 as
select t1.*
,max(case when days_dt_zx BETWEEN days_dt_1 and date_add(days_dt_1,30) then 1 else 0 end ) as had_0_30_zx
,max(case when days_dt_zx BETWEEN date_add(days_dt_1,31) and date_add(days_dt_1,60) then 1 else 0 end ) as had_31_60_zx
,max(case when days_dt_zx BETWEEN date_add(days_dt_1,61) and date_add(days_dt_1,90) then 1 else 0 end ) as had_61_90_zx
,max(case when days_dt_zx BETWEEN date_add(days_dt_1,91) and date_add(days_dt_1,120) then 1 else 0 end ) as had_91_120_zx
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN days_dt_1 and date_add(days_dt_1,30) ,1,0))  as with_0_30
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt_1,31) and date_add(days_dt_1,60)  ,1,0))  as with_31_60
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt_1,61) and date_add(days_dt_1,90)  ,1,0))  as with_61_90
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2)) BETWEEN date_add(days_dt_1,91) and date_add(days_dt_1,120)  ,1,0))  as with_91_120
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN days_dt_1 and date_add(days_dt_1,30) and prod_cd = '5103',1,0))  as with_0_30_5103
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt_1,31) and date_add(days_dt_1,60) and prod_cd = '5103' ,1,0))  as with_31_60_5103
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2))  BETWEEN date_add(days_dt_1,61) and date_add(days_dt_1,90) and prod_cd = '5103' ,1,0))  as with_61_90_5103
,max(if(concat(substr(day_time,1,4),'-',substr(day_time,5,2),'-',substr(day_time,7,2)) BETWEEN date_add(days_dt_1,91) and date_add(days_dt_1,120) and prod_cd = '5103' ,1,0))  as with_91_120_5103
from (
  SELECT uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,date_sub(days_dt,1) as days_dt_1
  from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_1
)t1
left outer join ( select id_unqp, dt, concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt_zx
  from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary  --征信里的表
  where dt>='20251001' and dt <'20260310'
  group by id_unqp, dt
)t2
on t1.uuid = t2.id_unqp
left outer join (
  -- 去重 提现表
                SELECT unique_id, user_id, bhv_time, event, aprv_status , day_time, instal_terms, wdraw_apply_amt, final_loan_amt,prod_cd
                FROM dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
                where dt='get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
                  and day_time >='20251001' and day_time < '20260310'
                  and unique_id is not NULL
                  group by unique_id, user_id, bhv_time, event, aprv_status , day_time, instal_terms, wdraw_apply_amt, final_loan_amt,prod_cd
)t3
on t1.uuid = t3.unique_id
group by uuid,t1.user_id,pril_bal,crdt_lim_yx,pril_bal_rate,t1.dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,days_dt_1
;

--用来统计分析文档里的数据的
SELECT count(1) as num, count(DISTINCT uuid) as usr_num
,sum(if(no_balance_flg_30=1 and with_0_30 = 0,1,0)) as no_balance_flg_30
,sum(if(no_balance_flg_60=1 and with_0_30 +with_31_60 = 0,1,0)) as no_balance_flg_60
,sum(if(no_balance_flg_90=1 and with_0_30 +with_31_60 +with_61_90= 0,1,0)) as no_balance_flg_90
,sum(if(no_balance_flg_30=1 and with_0_30_5103 = 0,1,0)) as no_balance_flg_30_5103
,sum(if(no_balance_flg_60=1 and with_0_30_5103 +with_31_60_5103 = 0,1,0)) as no_balance_flg_60_5103
,sum(if(no_balance_flg_90=1 and with_0_30_5103 +with_31_60_5103 +with_61_90_5103= 0,1,0)) as no_balance_flg_90_5103
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
-- and pril_bal_rate >= 0.5
and had_0_30_zx =1
and had_31_60_zx =1
and had_61_90_zx=1
and had_91_120_zx=1
;

--征信需要的数据，放到一个表里--
---把机构代码搞出来--
--特殊的是我们的机构代码--
create table if not exists lj_iceberg.ai_decision_dev.analyse_user_260612_zyy_03 as
SELECT t1.id_unqf, --征信文件编码，唯一
t1.id_unqp, --用户id
t1.account_no, --账户no，在一份文件里可以拿来关联
coalesce(if(t1.balance='',0,t1.balance),0) as balance, --余额
t2.org_manage_type, --机构代码
t2.org_manage_code,
coalesce(if(t2.credit_grant_amount='',0,t2.credit_grant_amount),0) as credit_grant_amount, --授信额度
t1.dt -- 征信的日期
from (select id_unqf,id_unqp,
account_no,
account_state,
close_date,
turn_out_date,
balance,
latest_repayment_date,
latest_repayment_amount,
level5_type,
repayment_state,
info_date,
time_inst,dt
from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform
  where dt>='20251001' and dt <'20260201'
  and (close_date is null or close_date = '')
  -- and  (balance is not NULL  and balance !='' and balance>0)
  )t1
join (
  select id_unqf, account_no,id_unqp,
  credit_serial_no,
account_type,
org_manage_type,
org_manage_code,
account_id,
open_date,
end_date,
loan_amount,
currency_type,
busi_type,
assure_type,
payment_payment,
payment_frequency,
payment_type,
loan_together_state,
credit_grant_amount,
share_credit_amount,
loan_give_type,
payment_state_transfer,dt
from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
  where dt>='20251001' and dt <'20260201'
  and account_type in ('R1','R2','R3') --只关注R1、R2、R3
)t2
on t1.id_unqf = t2.id_unqf and t1.account_no = t2.account_no
and t1.id_unqp = t2.id_unqp and t1.dt = t2.dt
  ;


-- 关联征信数据--
-- drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_3;
create table if not exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_3 as
select t1.*
,account_no,balance,org_manage_type,credit_grant_amount,t2.dt as dt_zx,org_manage_code
from (
  select uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,days_dt_1
    ,had_0_30_zx,had_31_60_zx,had_61_90_zx,had_91_120_zx
    ,with_0_30,with_31_60,with_61_90,with_91_120
    ,with_0_30_5103,with_31_60_5103,with_61_90_5103,with_91_120_5103
  from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
)t1
left join (
  select id_unqp,id_unqf,account_no,coalesce(balance,0) as balance,org_manage_type,credit_grant_amount,dt,org_manage_code
  , concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt_zx
 from lj_iceberg.ai_decision_dev.analyse_user_260612_zyy_03
)t2
on t1.uuid = t2.id_unqp
where (days_dt_zx BETWEEN days_dt_1 and date_add(days_dt_1,60) or days_dt_zx is null)
;


--将上述表 按用户+征信维度加工余额、授信额度 T10156530H0001是马消
-- drop table if exists  lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_4;
create table if not exists  lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_4 as
SELECT uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,days_dt_1
    ,had_0_30_zx,had_31_60_zx,had_61_90_zx,had_91_120_zx,dt_zx
    ,with_0_30,with_31_60,with_61_90,with_91_120
    ,with_0_30_5103,with_31_60_5103,with_61_90_5103,with_91_120_5103
    ,yye_account_num,balance,balance_max,balance_min,credit_grant_amount
,credit_grant_amount_max,credit_grant_amount_min
,row_number() over (partition by uuid order by dt_zx) as zx_rank
,row_number() over (PARTITION by uuid order by balance desc ) as balance_rank
from ( select uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,days_dt_1
    ,had_0_30_zx,had_31_60_zx,had_61_90_zx,had_91_120_zx,dt_zx
    ,with_0_30,with_31_60,with_61_90,with_91_120
    ,with_0_30_5103,with_31_60_5103,with_61_90_5103,with_91_120_5103
,sum(if(balance >0 and org_manage_code <> 'T10156530H0001',1,0)) as yye_account_num
,sum(if(balance >0 and org_manage_code <> 'T10156530H0001',balance,0)) as balance
,max(if(balance >0 and org_manage_code <> 'T10156530H0001',balance,0)) as balance_max
,min(if(balance>0 and org_manage_code <> 'T10156530H0001',balance,null)) as balance_min
,sum(if(balance >0 and org_manage_code <> 'T10156530H0001',credit_grant_amount,0)) as credit_grant_amount
,max(if(balance >0 and org_manage_code <> 'T10156530H0001',credit_grant_amount,0)) as credit_grant_amount_max
,min(if(balance >0 and org_manage_code <> 'T10156530H0001',credit_grant_amount,0)) as credit_grant_amount_min
  from  lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_3
  group by uuid,user_id,pril_bal,crdt_lim_yx,pril_bal_rate,dt,days_dt,no_balance_flg_30,no_balance_flg_60,no_balance_flg_90,days_dt_1
    ,had_0_30_zx,had_31_60_zx,had_61_90_zx,had_91_120_zx,dt_zx
    ,with_0_30,with_31_60,with_61_90,with_91_120
    ,with_0_30_5103,with_31_60_5103,with_61_90_5103,with_91_120_5103
)t1
;

--统计最早的那份征信的余额 和 最大的余额，统计余额有增加的用户数量
-- 统计有需求
SELECT if(balance_max>first_balance,1,0) as flg
,count(1) as num
from (select uuid
,max(if(zx_rank=1,balance,0)) as first_balance -- 最早那份征信的余额
,max(balance) as balance_max -- 最大的余额
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_4
where crdt_lim_yx >= 20000
-- and pril_bal_rate >=0.5
and had_0_30_zx =1
and had_31_60_zx =1
and had_61_90_zx=1
-- and had_91_120_zx=1
-- and no_balance_flg_60 =1
-- and with_0_30 + with_31_60 = 0
and no_balance_flg_90 =1
and with_0_30 + with_31_60 + with_61_90= 0
group by uuid
)tt
group by if(balance_max>first_balance,1,0)
;
