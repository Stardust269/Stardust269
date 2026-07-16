# 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage)
page_id: 39c617cf-3593-8083-9348-da01832d603e


| 字段名称 | 数值类型 | 字段编码 | 数据格式 | 字段解释 |
| 主键ID | long | id |  | 自增主键ID |
| 报告ID | varchar(32) | id_unqf |  | 报告ID |
| 客户ID | varchar(32) | id_unqp |  | 客户ID |
| 账户标识 | varchar(60) | account_no |  | 账户标识 |
| 大额专项分期额度 | int(15) | amount |  | 该账户下大额专项分期的额度 |
| 分期额度生效日期 | date | effect_date |  | 该账户下大额专项分期的额度生效日 |
| 分期额度到期日期 | date | expire_date |  | 大额专项分期的额度有效截止日 |
| 已用分期金额 | int(15) | amount_used |  | 已经使用的大额专项分期金额 |
| 插入时间 | datatime | time_inst |  | 插入时间 |