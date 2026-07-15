# 信贷交易信息概要-被追偿信息汇总明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail)
page_id: 39c617cf-3593-809d-af19-d757bc9c7eb6


| 备注 | 数值类型 | 字段解释 | 字段编码 | 字段名称 |
|  | long | 自增主键ID | id | 主键ID |
|  | varchar(32) | 报告ID | id_unqf | 报告ID |
|  | varchar(32) | 客户ID | id_unqp | 客户ID |
| 对应字典：recovered_collect_type_code | varchar(16) | 被追偿业务类型 | cre_tran_pro_type | 被追偿业务类型 |
|  | int | 账户数 | account_num | 账户数 |
|  | int | 被追偿余额 | balance | 余额 |
|  | datetime | 插入时间 | time_inst | 插入时间 |