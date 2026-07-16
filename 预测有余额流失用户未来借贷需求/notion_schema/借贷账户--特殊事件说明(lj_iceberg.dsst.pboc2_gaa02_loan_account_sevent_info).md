# 借贷账户--特殊事件说明(lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info)
page_id: 39c617cf-3593-80df-a332-f6376bfcf780


| 字段名称 | 数值类型 | 数据格式 | 字段解释 | 字段编码 |
| 主键ID | long |  | 自增主键ID | id |
| 报告ID | varchar(32) |  | 报告ID | id_unqf |
| 客户ID | varchar(32) |  | 客户ID | id_unqp |
| 账户标识 | varchar(60) |  | 账户标识 | account_no |
| 特殊事件发生月份 | varchar(12) | yyyy-mm | 特殊事件发生月份 | occur_month |
| 特殊事件类型 | varchar(12) |  | 特殊事件类型 | sevent_type |
| 插入时间 | datatime |  | 插入时间 | time_inst |