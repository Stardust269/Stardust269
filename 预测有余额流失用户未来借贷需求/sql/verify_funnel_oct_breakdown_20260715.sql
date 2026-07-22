-- =============================================================================
-- 十月漏斗拆因诊断：解释 step1/2/3 与同事预期数字的差异
-- 在 verify_funnel_oct_20260715.sql 之后跑
-- =============================================================================

-- ---------- Step1：行数 vs 去重 uuid vs 多 user_id ----------
select
    count(1) as step1_rows,
    count(distinct uuid) as step1_uuid,
    count(distinct concat(uuid, '|', user_id)) as step1_uuid_user
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
where rk = 1 and m = '202510';
-- 若 step1_rows(5085241) > step1_uuid(≈5022793)，差额来自同一 uuid 多个 user_id

-- ---------- Step2：逐层加条件，看哪一步逼近同事 386311 ----------
select
    count(1) as s2a_full_channel_nb_only
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715
where m = '202510';
-- 当前 pf 表 ≈ 586392（仅全渠道 no_balance_60）

select
    count(1) as s2b_nb_plus_no_with
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510'
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;
-- 同事 step2 统计含「未发起贷款」；加 with 后应明显小于 586392

-- 临时重算：5103 渠道 60 天内也变无余额（我方主流程已去掉，此处仅诊断）
select
    count(1) as s2c_nb_no_with_and_5103_nb
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
where pf.m = '202510'
  and exists (
      select 1
      from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 nb
      where nb.uuid = pf.uuid and nb.user_id = pf.user_id and nb.dt = pf.dt
        and nb.no_balance_flg_60_5103 = 1
  );
-- 若 nb 表无 no_balance_flg_60_5103 列，跑下面 s2c_rebuild 段

-- 重算 5103 无余额（不依赖旧列）
with pf_oct as (
    select * from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 where m = '202510'
),
nb_5103 as (
    select
        t1.uuid, t1.user_id, t1.dt,
        max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 60), t2.flg, 0)) as nb_5103_60
    from pf_oct t1
    left join (
        select uuid, user_id,
               concat(substr(dt,1,4),'-',substr(dt,5,2),'-',substr(dt,7,2)) as days_dt,
               if(if_lend='复贷' and cust_types_01='无余额', 1, 0) as flg
        from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
        where dt between '20250831' and '20260201'
          and sx_rowid = 1 and prod_cd = '5103'
    ) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    group by t1.uuid, t1.user_id, t1.dt
)
select
    count(1) as s2c_rebuild_nb_and_5103nb,
    sum(if(i.with_0_30 + i.with_31_60 = 0, 1, 0)) as s2d_also_no_with
from nb_5103 n
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 i
  on n.uuid = i.uuid and n.user_id = i.user_id and n.dt = i.dt
where n.nb_5103_60 = 1;
-- s2d 应最接近同事 386311

-- ---------- Step3：完整 cohort vs 权威 5401 ----------
select
    count(1) as step3_cohort_rows,
    count(distinct uuid) as step3_cohort_uuid
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where m = '202510';

select
    count(1) as step3_had_no_with_from_pf,
    sum(if(with_0_30 + with_31_60 = 0 and had_0_30_zx = 1 and had_31_60_zx = 1, 1, 0)) as pass_all
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510';

select
    count(1) as overlap_5401_uuid,
    sum(if(j.uuid is not null and a.uuid is null, 1, 0)) as jcr_only,
    sum(if(j.uuid is null and a.uuid is not null, 1, 0)) as auth5401_only
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j
full outer join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 a
  on j.uuid = a.uuid
where j.m = '202510' or j.m is null;
