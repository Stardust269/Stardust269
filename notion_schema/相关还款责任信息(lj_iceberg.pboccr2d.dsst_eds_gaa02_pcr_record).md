# 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record)
page_id: 39c617cf-3593-8073-be2b-c478fa812fce


| 字段名称 | 备注 | 数值类型 | 字段编码 | 字段解释 |
| 主键ID |  | long | id | 自增主键ID |
| 报告ID |  | varchar(32) | id_unqf | 报告ID |
| 客户ID |  | varchar(32) | id_unqp | 客户ID |
| 主借款人身份类别 | 对应字典表：identity_type_code | varchar(16) | main_loaner_type | 主借款人身份类别 |
| 业务管理机构类型 | 对应字典表：institution_type_code | varchar(16) | org_manage_type | 业务管理机构类型 |
| 业务管理机构 |  | varchar(16) | org_manage | 业务管理机构 |
| 业务种类 | 当identity为个人时，对应字典:loan_business_type_code当identity为企业时，对应字典：business_loan_btype_code | varchar(16) | busi_type | 业务种类 |
| 开立日期 |  | date | open_date | 开立日期 |
| 到期日期 |  | date | end_date | 到期日期 |
| 相关还款人责任人类型 | 对应字典表：loan_repay_liability_type_code | varchar(32) | duty_type | 相关还款人责任人类型 |
| 保证合同编号 |  | varchar(64) | contract_no | 保证合同编号 |
| 相关还款责任金额 |  | int | duty_amount | 相关还款责任金额 |
| 币种 | 对应字典：币种 | varchar(16) | currency_type | 币种 |
| 余额 |  | int | balance | 余额 |
| 五级分类 | 对应字典：risk_account_level | varchar(16) | level5 | 五级分类 |
| 账户类型 | 当身份类别为个人时，对应字典表：loan_account_type_code为企业时：返回为空 | varchar(16) | account_type | 账户状态 |
| 还款状态 | 当身份类别为个人时，对应字典表：loan_account_type_code为企业时：返回空 | varchar(16) | repay_status | 还款状态 |
| 逾期月数 |  | int | due_month_num | 逾期月数 |
| 信息报告日期 |  | date | info_date | 信息报告日期 |
| 系统插入时间 |  | datetime | time_inst | 系统插入时间 |