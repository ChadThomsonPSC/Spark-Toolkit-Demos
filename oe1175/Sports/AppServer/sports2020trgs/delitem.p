/***************************************************************************\
*****************************************************************************
**
**     Program: delitem.p
**    Descript:
**
*****************************************************************************
\***************************************************************************/

trigger procedure for delete of Item.

for each bin of item:
    delete bin.
end. /*for each bin*/