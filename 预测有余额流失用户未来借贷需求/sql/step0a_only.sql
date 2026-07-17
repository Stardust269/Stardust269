-- Step 0a 单独执行（只提交本文件；若表已存在请先手动 drop）
-- 若报 create or replace 错误：平台不支持，请用 create table
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623;

create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623 as
select
    uuid, user_id, pril_bal, crdt_lim_yx,
    pril_bal / crdt_lim_yx as pril_bal_rate,
    curt_crdt_line_yx,
    pril_bal / curt_crdt_line_yx as pril_bal_rate_1,
    crdt_lim_op,
    pril_bal / crdt_lim_op as pril_bal_rate_2,
    dt,
    row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_yx) as rk,
    row_number() over (partition by uuid, user_id order by pril_bal / curt_crdt_line_yx) as rk_1,
    row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_op) as rk_2
from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
where dt >= '20251002' and dt <= '20251101'
  and sx_rowid = 1
  and prod_cd = '5103'
  and if_lend = '复贷'
  and cust_types_01 = '有余额'
  and crdt_lim_yx > 0
;
