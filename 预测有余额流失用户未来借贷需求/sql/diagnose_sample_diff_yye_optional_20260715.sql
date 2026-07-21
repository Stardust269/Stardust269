-- =============================================================================
-- 可选：与同事 yye_* 表逐步对齐（需先跑 yye_pril_bal_sample_reference_20260715.sql）
-- =============================================================================
-- 若报错 Object 'yye_pril_bal_info_20260715' not found → 同事表未建，跳过本文件即可
-- 无 yye 表时，用 diagnose_sample_diff_20260715.sql 的 Part B 代替（在 jcr_nb 上重算同事口径）
-- =============================================================================

-- D1 Step0a raw rk=1
select 'D1_raw_rk1' as step,
       j.m,
       count(1) as jcr_cnt,
       (select count(1) from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715 y
        where y.rk = 1 and y.m = j.m) as yye_cnt,
       count(1) - (select count(1) from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715 y
                   where y.rk = 1 and y.m = j.m) as diff
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 j
where j.rk = 1
group by j.m
order by j.m
;

-- D2 Step0b nb
select 'D2_nb' as step,
       j.m,
       count(1) as jcr_cnt,
       (select count(1) from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_1 y
        where y.m = j.m) as yye_cnt,
       count(1) - (select count(1) from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_1 y
                   where y.m = j.m) as diff
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 j
group by j.m
order by j.m
;

-- D3 同事 _2 表 3 条件 pnum（权威对照）
select 'D3_yye_pnum_3cond' as step, m,
       count(1) as total_rows,
       count(distinct uuid) as uuid_cnt,
       sum(if(with_0_30 + with_31_60 = 0 and no_balance_flg_60 = 1, 1, 0)) as pnum_3cond
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2
where crdt_lim_yx >= 20000
group by m
order by m
;
