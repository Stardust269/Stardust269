# 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail)
page_id: 39c617cf-3593-808d-924f-fd6ab7c7218e


| 备注 | 字段名称 | 数值类型 | 字段解释 | 字段编码 |
|  | 主键ID | long | 自增主键ID | id |
|  | 报告ID | varchar(32) | 报告ID | id_unqf |
|  | 客户ID | varchar(32) | 客户ID | id_unqp |
| 对应字典：cre_tran_pro_type_code | 业务类型 | varchar(16) | 业务类型 | cre_tran_pro_type |
| 对应字典：cre_tran_pro_cate_code | 业务大类 | varchar(16) | 业务大类 | cre_tran_pro_cate_code |
|  | 账户数 | int | 账户数 | account_num |
|  | 首笔业务发放月份 | varchar(16) | 首笔业务发放月份 | first_business_month |
|  | 插入时间 | datetime | 插入时间 | time_inst |