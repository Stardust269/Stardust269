# 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record)
page_id: 39c617cf-3593-80c0-a9ad-e6bc65e27099


| 字段解释 | 字段编码 | 字段名称 | 征信报告数据获取来源 | 数值类型 |
| 自增主键ID | id | 主键ID |  | long |
| 报告ID | id_unqf | 报告ID |  | varchar(32) |
| 客户ID | id_unqp | 客户ID |  | varchar(32) |
| 后付费账户类型 | account_type | 后付费账户类型 | 对应字典：post_pay_type_code | varchar(32) |
| 机构名称 | org_name | 机构名称 |  | varchar(32) |
| 后付费业务类型 | busi_type | 业务类型 | 对应字典：tel_pay_bus_code | varchar(16) |
| 业务开通日期 | busi_open_date | 业务开通日期 |  | date |
| 当前缴费状态 | status_payment | 当前缴费状态 | 对应字典：tel_pay_account_status_code | varchar(16) |
| 当前欠费金额 | arrears_amount | 当前欠费金额 |  | int |
| 记账日期 | account_date | 记账日期 |  | date |
| 最近24月缴费记录 | payment_record_24m | 最近24月缴费记录 |  | varcahr(64) |
| 系统插入时间 | time_inst | 系统插入时间 |  | datetime |
可直接用于模型训练的特征共4项：
24月缴费记录的逾期模式（连续欠费月数+近期欠费频率）→ 行为稳定性的核心指标；
当前欠费金额的相对严重度（分箱处理）→ 量化即时风险等级；
当前缴费状态的风险等级（二值化高风险状态）→ 触发风控规则的关键信号；
账户活跃时长（动态计算）→ 修正风险判断的上下文基准。