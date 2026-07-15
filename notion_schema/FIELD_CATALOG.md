# 字段编码总表（从全部子页面汇总）

## lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |
| 账户标识 | `account_no` | varchar(60) | 账户标识 | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |
| 大额专项分期额度 | `amount` | int(15) | 该账户下大额专项分期的额度 | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |
| 分期额度生效日期 | `effect_date` | date | 该账户下大额专项分期的额度生效日 | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |
| 分期额度到期日期 | `expire_date` | date | 大额专项分期的额度有效截止日 | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |
| 已用分期金额 | `amount_used` | int(15) | 已经使用的大额专项分期金额 | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 借贷账户--大额专项分期信息(lj_iceberg.dsst.pboc2_gaa02_loan_account_lamount_stage) |

## lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 借贷账户--特殊事件说明(lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 借贷账户--特殊事件说明(lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info) |
| 账户标识 | `account_no` | varchar(60) | 账户标识 | 借贷账户--特殊事件说明(lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info) |
| 特殊事件发生月份 | `occur_month` | varchar(12) | 特殊事件发生月份 | 借贷账户--特殊事件说明(lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info) |
| 特殊事件类型 | `sevent_type` | varchar(12) | 特殊事件类型 | 借贷账户--特殊事件说明(lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 借贷账户--特殊事件说明(lj_iceberg.dsst.pboc2_gaa02_loan_account_sevent_info) |

## lj_iceberg.dsst.pboc2_gaa02_pca_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 授信协议编号 | `credit_serial_no` | varchar(32) | 授信协议编号 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 业务管理机构 | `org_name` | varchar(16) | 业务管理机构 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 授信协议标识 | `identification` | varchar(32) | 授信协议标识 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 生效日期 | `start_date` | date | 生效日期 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 到期日期 | `end_date` | date | 到期日期 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 授信额度用途 | `credit_purpose` | varchar(16) | 授信额度用途 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 授信额度 | `credit_amount` | int | 授信额度 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 授信限额 | `limit_amount` | int | 授信限额 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 授信限额编号 | `limit_no` | varchar(64) | 授信限额编号 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 已用额度 | `use_amount` | int | 已用额度 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 币种 | `currency_type` | varchar(16) | 币种 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 业务管理机构类型 | `busi_org_type` | varchar(16) | 业务管理机构类型 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 授信协议状态 | `status` | varchar(16) | 授信协议状态 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |
| 插入时间 | `time_inst` | datetime | 插入时间 | 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record） |

## lj_iceberg.dsst.pboc2_gaa02_pcj_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 立案法院 | `court_file` | varchar(64) | 立案法院 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 案由 | `reason` | varchar(256) | 判决案由 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 立案日期 | `date_file_case` | date | 立案日期 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 结案方式 | `type_close_way` | varchar(16) | 结案方式 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 判决/调解结果 | `result` | varchar(256) | 判决/调解结果 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 判决/调解生效日期 | `efffect_date` | date | 判决/调解生效日期 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 诉讼标的 | `sub_litigation` | varchar(16) | 诉讼标的 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 诉讼标的金额 | `sub_litigation_amount` | int | 诉讼标的金额 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |
| 系统插入时间 | `time_inst` | datetime | 系统插入时间 | 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record) |

## lj_iceberg.dsst.pboc2_gaa02_person_risk_score

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score) |
| 个人得分(score) | `score` | int | 个人得分 | 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score) |
| 得分相对位置 | `position_num` | int | 得分相对位置 | 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score) |
| 分数说明1 | `score_affect` | varchar(8) | 分数说明1 | 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score) |
| 分数说明2 | `score_affect2` | varchar(8) | 分数说明2 | 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score) |

## lj_iceberg.dsst.pboc2_gaa02_reward_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |
| 编号 | `no_reward` | varchar(32) | 编号 | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |
| 奖励机构 | `reward_org` | varchar(32) | 奖励机构 | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |
| 奖励内容 | `reward_content` | varchar(128) | 奖励内容 | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |
| 生效日期 | `start_date` | date | 生效日期 | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |
| 截止日期 | `end_date` | date | 截止日期 | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record) |

## lj_iceberg.dsst.pboc2_gaa02_self_content

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 本人声明(lj_iceberg.dsst.pboc2_gaa02_self_content) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 本人声明(lj_iceberg.dsst.pboc2_gaa02_self_content) |
| 编号 | `no_selfsta` | int |  | 本人声明(lj_iceberg.dsst.pboc2_gaa02_self_content) |
| 声明内容 | `con_sta` | varchar(300) |  | 本人声明(lj_iceberg.dsst.pboc2_gaa02_self_content) |
| 添加日期 | `time_addselfsta` | date |  | 本人声明(lj_iceberg.dsst.pboc2_gaa02_self_content) |
| 系统插入记录时间 | `time_inst` | datetime |  | 本人声明(lj_iceberg.dsst.pboc2_gaa02_self_content) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |
| 数据块类型 | `common_data_block_type` | varchar(60) | 数据块标识 | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |
| 数据ID | `data_id` | varchar(60) | 数据ID | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |
| 标注及声明类型 | `label_declare_type` | varchar(8) | 标注及声明类型 | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |
| 标注或声明内容 | `label_content` | varchar(256) | 标注或声明内容 | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |
| 数据添加日期 | `add_date` | date | 添加日期 | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 非信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 非信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary) |
| 后付费业务类型 | `fee_delay_type` | varchar(32) | 后付费业务类型 | 非信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary) |
| 欠费账户数 | `arrears_account_num` | short(8) | 欠费账户数 | 非信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary) |
| 欠费金额 | `arrears_amount` | int | 欠费金额 | 非信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 非信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |
| 借款人身份类别 | `ptype` | varchar(8) | 借款人身份类别 | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |
| 还款责任类型 | `loan_repay_liability_type` | varchar(8) | 担保责任;其他相关还款责任 | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |
| 账户数 | `acount_num` | int | 账户数 | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |
| 还款责任金额 | `debt_duty_amount` | int | 还款责任金额 | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |
| 余额 | `balance` | int | 余额 | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 账户数合计 | `account_num` | short(8) | 账户数合计 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 业务类型数量 | `business_type_num` | short(8) | 业务类型数量 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 被追偿账余额合计 | `recovery_balance` | int | 被追偿账余额合计 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 被追偿业务类型数量 | `recovery_business_type_num` | short(8) | 被追偿业务类型数量 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 呆账账户数 | `bad_debt_account_num` | short(8) | 呆账账户数 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 呆账余额 | `bad_debt_balance` | int | 呆账余额 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 非循环贷账户汇总信息段-管理机构数 | `ncl_org_num` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 非循环贷账户汇总信息段-账户数 | `ncl_account_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 非循环贷账户汇总信息段-授信总额 | `ncl_credit_amount` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 非循环贷账户汇总信息段-余额 | `ncl_balance` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 非循环贷账户汇总信息段-最近六个月平均应还款 | `ncl_avg6m_repayment` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环贷账户汇总信息段-管理机构数 | `cl_org_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环贷账户汇总信息段-账户数 | `cl_account_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环贷账户汇总信息段-授信总额 | `cl_credit_amount` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环贷账户汇总信息段-余额 | `cl_balance` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环贷账户汇总信息段-最近六个月平均应还款 | `cl_avg6m_repayment` | int | 账户数 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环额度下分账户汇总信息段-管理机构数 | `clsa_org_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环额度下分账户汇总信息段-账户数 | `clsa_account_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环额度下分账户汇总信息段-授信总额 | `clsa_credit_amount` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环额度下分账户汇总信息段-余额 | `clsa_balance` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 循环额度下分账户汇总信息段-最近六个月平均应还款 | `clsa_avg6m_repayment` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 贷记卡账户汇总--账户数 | `credit_account_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 贷记卡账户汇总--发卡机构数 | `credit_org_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 贷记卡账户汇总--授信总额 | `credit_amount` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 贷记卡账户汇总--单家机构最高授信额 | `credit_amount_sigle_max` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 贷记卡账户汇总--单家机构最低授信额 | `credit_amount_sigle_min` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 贷记卡账户汇总--已用额度/透支额度 | `credit_used_amount` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 贷记卡账户汇总--最近6个月平均使用额度/透支额度 | `credit_used_amount_avg6m` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 准贷记卡账户汇总--账户数 | `scredit_account_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 准贷记卡账户汇总--发卡机构数 | `scredit_org_num` | short(8) |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 准贷记卡账户汇总--授信总额 | `scredit_amount` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 准贷记卡账户汇总--单家机构最高授信额 | `scredit_amount_sigle_max` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 准贷记卡账户汇总--单家机构最低授信额 | `scredit_amount_sigle_min` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 准贷记卡账户汇总--已用额度/透支额度 | `scredit_used_amount` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 准贷记卡账户汇总--最近6个月平均使用额度/透支额度 | `scredit_used_amount_avg6m` | int |  | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 相关还款责任个数 | `duty_num_repayment` | short(8) | 相关还款责任个数 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |
| 业务类型 | `cre_tran_pro_type` | varchar(16) | 业务类型 | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |
| 账户数 | `account_num` | int | 账户数 | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |
| 逾期月份数 | `num_month` | int | 总共逾期的次数 | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |
| 单月最高逾期/透支金额 | `amt_pdtotal` | long | 单月最高逾期/透支金额 | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |
| 最长逾期/透支月数 | `first_business_month` | varchar(16) | 首笔业务发放月份 | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 信贷交易信息概要-被追偿信息汇总明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 信贷交易信息概要-被追偿信息汇总明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail) |
| 被追偿业务类型 | `cre_tran_pro_type` | varchar(16) | 被追偿业务类型 | 信贷交易信息概要-被追偿信息汇总明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail) |
| 账户数 | `account_num` | int | 账户数 | 信贷交易信息概要-被追偿信息汇总明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail) |
| 余额 | `balance` | int | 被追偿余额 | 信贷交易信息概要-被追偿信息汇总明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 信贷交易信息概要-被追偿信息汇总明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_recovery_detail) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail) |
| 业务类型 | `cre_tran_pro_type` | varchar(16) | 业务类型 | 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail) |
| 业务大类 | `cre_tran_pro_cate_code` | varchar(16) | 业务大类 | 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail) |
| 账户数 | `account_num` | int | 账户数 | 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail) |
| 首笔业务发放月份 | `first_business_month` | varchar(16) | 首笔业务发放月份 | 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 信贷交易信息概要--信贷交易提示信息段明细(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 账户编号 | `account_no` | varchar(32) | 账户编号 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 授权协议编号 | `credit_serial_no` | varchar(32) | 征信系统分配给该协议在本报告中的唯一编号 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 账户类型 | `account_type` | varchar(16) | 账户类型（枚举） | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 业务管理机构类型 | `org_manage_type` | varchar(16) | 业务管理机构类型(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 业务管理机构代码 | `org_manage_code` | varchar(32) | 业务管理机构代码 数据提供机构内部具体负责借款人账户管理、信息核 实和相关异议处理的网点 /分支机构在征信系统中的 唯一编码。 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 账户标识 | `account_id` | varchar(60) | 账户标识在征信系统全局范围内用于唯一识别一个借贷账户的标识码 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 开立日期 | `open_date` | date | 开立日期 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 到期日期 | `end_date` | date | 到期日期 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 借款金额 | `loan_amount` | int(15) | 借款金额 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 币种 | `currency_type` | varchar(16) | 币种(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 业务种类 | `busi_type` | varchar(32) | 业务种类(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 担保方式 | `assure_type` | varchar(16) | 担保方式(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 还款期数 | `payment_payment` | short(3) | 还款期数 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 还款频率 | `payment_frequency` | varchar(16) | 还款频率 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 还款方式 | `payment_type` | varchar(16) | 还款方式(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 共同借款标识 | `loan_together_state` | varchar(16) | 共同借款状态(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 账户授信额度 | `credit_grant_amount` | int(15) | 账户授信额度 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 共享授信额度 | `share_credit_amount` | int(15) | 共享授信额度 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 贷款发放形式 | `loan_give_type` | varchar(16) | 贷款发放形式(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 债权转移时的还款状态 | `payment_state_transfer` | varchar(16) | 债权转移时的还款状态(枚举) | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 账户标识 | `account_no` | varchar(60) | 账户标识 | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 特殊交易类型 | `strans_type` | varchar(16) | 特殊交易类型 | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 特殊交易发生日期 | `strans_date` | date | 反映特殊交易发生的日期 | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 到期日期变更月数 | `strans_month_update_num` | short | 特殊交易引起的到期日变更月数 | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 特殊交易发生金额 | `strans_amount` | int(15) | 反映特殊交易相应的发生金额 | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 特殊交易明细记录 | `strans_des` | varchar(256) | 特殊交易详细情况的描述 | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 账户标识 | `account_no` | varchar(60) | 账户标识 | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 起始年月最近24m | `m24_startm` | varchar(32) | 起始年月 | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 截止年月最近24m | `m24_endm` | varchar(32) | 截止年月 | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 还款状态信息(24m) | `repay_state_24m` | varchar(128) | 还款状态最近24m | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 起始年月最近5Y | `y5_startm` | varchar(32) |  | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 截止年月最近5Y | `y5_endm` | varchar(32) |  | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 还款状态信息(5y) | `repay_state_5y` | varchar(2056) | 还款状态5y | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 账户标识 | `account_no` | varchar(60) | 账户标识 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 月份 | `month` | varchar(12) | 月份 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 账户状态 | `account_state` | varchar(12) | 账户状态 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 余额 | `balance` | int | 余额 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 已用额度 | `used_amount` | int | 已用额度 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 未出单的大额专项分期余额 | `lsiw_balance` | int | 未出单的大额专项分期余额 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 五级分类 | `level5_type` | varchar(16) | 贷款五级分类 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 剩余还款期数 | `remain_repayment_period` | int | 剩余还款期数 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 结算/应还款日 | `settle_date` | date | 结算/应还款日 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 本月应还款 | `repayment_amount` | int | 本月应还款 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 本月实还款 | `actual_repayment_amount` | int | 本月实还款 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 最近一次还款日期 | `latest_repayment_date` | date | 最近一次还款日期 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 当前逾期期数 | `overdue_period` | int | 当前逾期期数 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 当前逾期总额 | `overdue_amount_total` | int | 当前逾期总额 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 逾期31—60天未还本金 | `overdue_pd2_amount` | int | 逾期31—60天未还本金 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 逾期61－90天未还本金 | `overdue_pd3_amount` | int | 逾期61－90天未还本金 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 逾期91－180天未还本金 | `overdue_pd456_amount` | int | 逾期91－180天未还本金 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 逾期180天以上未还本金 | `overdue_pd7_amount` | int | 逾期180天以上未还本金 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 透支180天以上未付余额 | `overdraw_pd7_amount` | int | 透支180天以上未付余额 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 最近6个月平均使用额度 | `ave6m_use_amount` | int | 最近6个月平均使用额度 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 最近6个月平均透支余额 | `ave6m_overdraft_amount` | int | 最近6个月平均透支余额 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 最大使用额度 | `max_use_amount` | int | 最大使用额度 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 最大透支余额 | `max_overdraft_amount` | int | 最大透支余额 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 信息报告日期 | `info_dt` | date | 信息报告日期 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 账户标识 | `account_id` | varchar(60) | 账户标识 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 账户状态 | `account_state` | varchar(16) | 账户状态(枚举) | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 关闭日期 | `close_date` | date | 关闭日期 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 转出年月 | `turn_out_date` | varchar(16) | 转出年月 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 余额 | `balance` | int | 余额 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 最近一次还款日期 | `latest_repayment_date` | date | 最近一次还款日期 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 最近一次还款金额 | `latest_repayment_amount` | int | 最近一次还款金额 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 五级分类 | `level5_type` | varchar(16) | 贷款五级分类(枚举) | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 还款状态 | `repayment_state` | varchar(16) | 还款状态(枚举) | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 信息报告日期 | `info_date` | date | 信息报告日期 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |
| 插入时间 | `time_inst` | datatime | 插入时间 | 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 处罚机构 | `punish_org` | varchar(32) |  | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 处罚内容 | `punish_content` | varchar(256) |  | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 处罚金额 | `punish_amount` | int |  | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 生效日期 | `start_date` | date |  | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 截止日期 | `end_date` | date |  | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 行政复议结果 | `ar_result` | varchar(32) |  | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |
| 系统插入时间 | `time_inst` | datetime |  | 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 编号 | `no_serial` | int | 编号 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 人员类别 | `person_type` | varchar(16) | 人员类别 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 所在地 | `location` | varchar(16) | 所在地 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 工作单位 | `company` | varchar(16) | 工作单位 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 家庭月收入 | `month_income` | int | 家庭月收入 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 申请日期 | `apply_date` | date | 申请日期 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 批准日期 | `approval_date` | date | 批准日期 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 信息更新日期 | `info_date` | date | 信息更新日期 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |
| 插入时间 | `time_inst` | datetime | 插入时间 | 低保救助记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pbs_record） |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 执行法院 | `court_exc` | varchar(100) |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 执行案由 | `rsn_excact` | varchar(50) |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 立案日期 | `date_filcase` | date |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 结案方式 | `type_cloway` | varchar(50) |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 案件状态 | `stu_case` | varchar(50) |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 结案日期 | `date_clocase` | date |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 申请执行标的 | `sub_appexc` | varchar(100) |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 申请执行标的价值 | `pri_appexcsub` | int |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 已执行标的 | `sub_perf` | varchar(100) |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 已执行标的金额 | `pri_perfsub` | decimal |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |
| 系统插入记录时间 | `time_inst` | datetime |  | 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 主借款人身份类别 | `main_loaner_type` | varchar(16) | 主借款人身份类别 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 业务管理机构类型 | `org_manage_type` | varchar(16) | 业务管理机构类型 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 业务管理机构 | `org_manage` | varchar(16) | 业务管理机构 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 业务种类 | `busi_type` | varchar(16) | 业务种类 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 开立日期 | `open_date` | date | 开立日期 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 到期日期 | `end_date` | date | 到期日期 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 相关还款人责任人类型 | `duty_type` | varchar(32) | 相关还款人责任人类型 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 保证合同编号 | `contract_no` | varchar(64) | 保证合同编号 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 相关还款责任金额 | `duty_amount` | int | 相关还款责任金额 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 币种 | `currency_type` | varchar(16) | 币种 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 余额 | `balance` | int | 余额 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 五级分类 | `level5` | varchar(16) | 五级分类 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 账户类型 | `account_type` | varchar(16) | 账户状态 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 还款状态 | `repay_status` | varchar(16) | 还款状态 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 逾期月数 | `due_month_num` | int | 逾期月数 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 信息报告日期 | `info_date` | date | 信息报告日期 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |
| 系统插入时间 | `time_inst` | datetime | 系统插入时间 | 相关还款责任信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pcr_record) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 就业状态 | `job_state` | varchar(8) | 就业状态 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 工作单位名称 | `company_name` | varchar(128) | 工作单位名称 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 单位性质 | `org_type` | varchar(32) | 单位性质 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 单位地址 | `company_address` | varchar(128) | 单位地址 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 单位地址经度 | `company_address_lng` | varchar(32) | 单位地址经度 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 单位地址维度 | `company_address_ltt` | varchar(32) | 单位地址维度 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 单位电话 | `telephone` | varchar(32) | 单位电话 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 职业 | `vocation` | varchar(32) | 职业 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 行业 | `industry` | varchar(32) | 行业 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 职务 | `job_type` | varchar(16) | 职务 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 职称 | `job_title_type` | varchar(16) | 职称 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 计入本单位年份 | `join_year` | shortint | 计入本单位年份 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 信息更新日期 | `update_date` | date | 信息更新日期 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |
| 插入时间 | `time_inst` | datatime | 插入时间 | 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info） |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金参缴地 | `addh_reg` | varchar(50) | 住房公积金参缴地 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金参缴日期 | `timeh_hf` | date | 住房公积金参缴日期 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金初缴月份 | `timeh_fstp` | varchar(8) | 住房公积金初缴月份 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金缴至月份 | `timeh_lstp` | varchar(8) | 住房公积金缴至月份 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金缴费状态 | `timeh_sts` | varchar(20) | 住房公积金缴费状态 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金月缴存额 | `amth_mp` | int | 住房公积金月缴存额 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金个人缴存比例 | `pcth_indp` | int | 住房公积金个人缴存比例 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金单位缴存比例 | `pcth_emp` | int | 住房公积金单位缴存比例 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金缴费单位 | `orgh` | varchar(100) | 住房公积金缴费单位 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 住房公积金信息更新日期 | `timeh_upd` | date | 住房公积金信息更新日期 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |
| 系统插入时间 | `time_inst` | datetime | 系统插入时间 | 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 后付费账户类型 | `account_type` | varchar(32) | 后付费账户类型 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 机构名称 | `org_name` | varchar(32) | 机构名称 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 业务类型 | `busi_type` | varchar(16) | 后付费业务类型 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 业务开通日期 | `busi_open_date` | date | 业务开通日期 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 当前缴费状态 | `status_payment` | varchar(16) | 当前缴费状态 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 当前欠费金额 | `arrears_amount` | int | 当前欠费金额 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 记账日期 | `account_date` | date | 记账日期 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 最近24月缴费记录 | `payment_record_24m` | varcahr(64) | 最近24月缴费记录 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |
| 系统插入时间 | `time_inst` | datetime | 系统插入时间 | 非信贷交易信息明细-后付费记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pnd_record) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_pot_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 欠税信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pot_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 欠税信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pot_record) |
| 主管税务机关 | `tax_org_manage` | varchar(32) | 主管税务机关 | 欠税信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pot_record) |
| 欠税总额 | `tax_owing_amount` | int | 欠税总额 | 欠税信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pot_record) |
| 欠税统计日期 | `stat_date` | date | 欠税统计日期 | 欠税信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pot_record) |
| 系统插入时间 | `time_inst` | datetime | 系统插入时间 | 欠税信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_pot_record) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_ppo_summary

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 公共信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppo_summary) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 公共信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppo_summary) |
| 信息类型 | `public_info_type` | varchar(32) | 信息类型 | 公共信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppo_summary) |
| 记录数 | `record_num` | int(11) | 记录数 | 公共信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppo_summary) |
| 涉及金额 | `amount` | int | 涉及金额 | 公共信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppo_summary) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 公共信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppo_summary) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 编号 | `no_serial` | int | 编号 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 执行资格名称 | `ppq_name` | varchar(64) | 执业资格名称 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 等级 | `level` | varchar(16) | 等级 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 获得日期 | `acquire_date` | date | 获得日期 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 到期日期 | `expire_date` | date | 到期日期 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 吊销日期 | `revoke_date` | date | 吊销日期 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 颁发机构 | `award_org` | varchar(32) | 颁发机构 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 机构所在地 | `org_location` | varchar(32) | 机构所在地 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record) |

## lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 上一次查询日期 | `last_query_date` | date | 上一次查询日期 | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 上一次查询机构类型 | `last_query_org_type` | varchar(32) | 上一次查询机构类型 | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 上一次查询机构代码 | `last_query_org_code` | varchar(32) | 上一次查询机构代码 | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 上一次查询原因 | `last_query_reason` | varchar(32) | 上一次查询原因 | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近一月内查询机构数(贷款审批) | `loan_audit_query_org_num_1m` | short(8) | 最近一月内查询机构数(贷款审批) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近一月内查询机构数(信用卡审批) | `credit_audit_query_org_num_1m` | short(8) | 最近一月内查询机构数(信用卡审批) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近一月内查询次数(贷款审批) | `loan_audit_query_num_1m` | short(8) | 最近一月内查询次数(贷款审批) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近一月内查询次数(信用卡审批) | `credit_audit_query_num_1m` | short(8) | 最近一月内查询次数(信用卡审批) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近一月内查询次数(本人查询) | `person_query_num_1m` | short(8) | 最近一月内查询次数(本人查询) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近两年内的查询次数(贷后管理) | `plm_query_num_2y` | short(8) | 最近两年内的查询次数(贷后管理) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近两年内的查询次数(担保资格审查) | `assure_query_num_2y` | short(8) | 最近两年内的查询次数(担保资格审查) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 最近两年内的查询次数(特约商户实名审查) | `sam_query_num_2y` | short(8) | 最近两年内的查询次数(特约商户实名审查) | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary) |

## lj_iceberg.pboccr2d.gaa02_query_record

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
| 报告ID | `id_unqf` | varchar(32) | 报告ID | 查询记录表(lj_iceberg.pboccr2d.gaa02_query_record) |
| 客户ID | `id_unqp` | varchar(32) | 客户ID | 查询记录表(lj_iceberg.pboccr2d.gaa02_query_record) |
| 查询日期 | `query_date` | date | 查询日期 | 查询记录表(lj_iceberg.pboccr2d.gaa02_query_record) |
| 查询机构 | `query_org` | varchar(32) | 查询机构 | 查询记录表(lj_iceberg.pboccr2d.gaa02_query_record) |
| 查询原因 | `query_reason` | varchar(16) | 查询原因 | 查询记录表(lj_iceberg.pboccr2d.gaa02_query_record) |
| 插入时间 | `time_inst` | datetime | 插入时间 | 查询记录表(lj_iceberg.pboccr2d.gaa02_query_record) |

## 需要加工的数据

| 字段名称 | 字段编码 | 数值类型 | 说明 | 来源页面 |
|---|---|---|---|---|
